import Foundation
import AppKit
import Combine
import CloudKit
import os.log

private let libraryLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "LibraryService")

/// Represents an item in the library
struct LibraryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: ItemType
    let fileName: String
    let createdAt: Date
    var collection: String?
    var isFavorite: Bool
    var cloudShareId: String?

    enum ItemType: String, Codable {
        case screenshot
        case recording
        case gif
        case voiceRecording
    }

    var fileExtension: String {
        switch type {
        case .screenshot: return "png"
        case .recording: return "mp4"
        case .gif: return "gif"
        case .voiceRecording: return "m4a"
        }
    }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Service for managing the library with iCloud sync
@MainActor
class LibraryService: ObservableObject {
    static let shared = LibraryService()

    @Published var items: [LibraryItem] = []
    @Published var collections: [String] = ["Screenshots", "Recordings", "Favorites"]
    @Published var iCloudAvailable: Bool = false
    @Published var syncStatus: SyncStatus = .idle

    enum SyncStatus {
        case idle
        case syncing
        case synced
        case error(String)
    }

    private let fileManager = FileManager.default
    private var localLibraryURL: URL
    private var iCloudLibraryURL: URL?
    private var manifestURL: URL {
        libraryURL.appendingPathComponent("manifest.json")
    }

    // Use iCloud if available, otherwise local
    private var libraryURL: URL {
        iCloudLibraryURL ?? localLibraryURL
    }

    // CloudKit for metadata sync
    private let container = CKContainer(identifier: "iCloud.com.instinctly.app")
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }

    // NSUbiquitousKeyValueStore for quick sync
    private let kvStore = NSUbiquitousKeyValueStore.default

    private var syncObserver: NSObjectProtocol?

    private init() {
        // Setup local fallback
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        localLibraryURL = appSupport.appendingPathComponent("Instinctly/Library", isDirectory: true)
        try? fileManager.createDirectory(at: localLibraryURL, withIntermediateDirectories: true)

        // Setup iCloud
        setupICloud()

        // Load existing items
        loadManifest()

        // Listen for iCloud changes
        setupICloudObservers()

        libraryLogger.info("📚 LibraryService initialized with \(self.items.count) items, iCloud: \(self.iCloudAvailable)")
    }

    // MARK: - iCloud Setup

    private func setupICloud() {
        // Check iCloud availability
        if let containerURL = fileManager.url(forUbiquityContainerIdentifier: "iCloud.com.instinctly.app") {
            iCloudLibraryURL = containerURL.appendingPathComponent("Documents/Library", isDirectory: true)

            // Create iCloud directory if needed
            if let url = iCloudLibraryURL {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }

            iCloudAvailable = true
            libraryLogger.info("☁️ iCloud available at: \(containerURL.path)")

            // Migrate local data to iCloud if needed
            migrateLocalToICloud()
        } else {
            iCloudAvailable = false
            libraryLogger.warning("⚠️ iCloud not available, using local storage")
        }
    }

    private func setupICloudObservers() {
        // Listen for NSUbiquitousKeyValueStore changes
        syncObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleICloudChange(notification)
            }
        }

        // Start syncing
        kvStore.synchronize()

        // Listen for iCloud account changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupICloud()
                self?.loadManifest()
            }
        }
    }

    private func handleICloudChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            libraryLogger.info("☁️ iCloud data changed, reloading...")
            loadManifest()

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            libraryLogger.warning("⚠️ iCloud quota exceeded")

        case NSUbiquitousKeyValueStoreAccountChange:
            libraryLogger.info("☁️ iCloud account changed")
            setupICloud()
            loadManifest()

        default:
            break
        }
    }

    private func migrateLocalToICloud() {
        guard iCloudAvailable, let iCloudURL = iCloudLibraryURL else { return }

        // Check if local has data and iCloud is empty
        let localManifest = localLibraryURL.appendingPathComponent("manifest.json")
        let iCloudManifest = iCloudURL.appendingPathComponent("manifest.json")

        guard fileManager.fileExists(atPath: localManifest.path),
              !fileManager.fileExists(atPath: iCloudManifest.path) else {
            return
        }

        libraryLogger.info("☁️ Migrating local library to iCloud...")

        // Copy all files to iCloud
        do {
            let localFiles = try fileManager.contentsOfDirectory(at: localLibraryURL, includingPropertiesForKeys: nil)
            for file in localFiles {
                let destURL = iCloudURL.appendingPathComponent(file.lastPathComponent)
                if !fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.copyItem(at: file, to: destURL)
                }
            }
            libraryLogger.info("✅ Migration complete")
        } catch {
            libraryLogger.error("❌ Migration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Items

    /// Save a screenshot to the library
    func saveScreenshot(_ image: NSImage, name: String? = nil, collection: String? = nil) throws -> LibraryItem {
        let id = UUID()
        let itemName = name ?? "Screenshot_\(formatDate())"
        let fileName = "\(id.uuidString).png"
        let fileURL = libraryURL.appendingPathComponent(fileName)

        // Convert and save image
        guard let data = ImageProcessingService.exportAsPNG(image) else {
            throw LibraryError.saveFailed
        }
        try data.write(to: fileURL)

        // Create item
        let item = LibraryItem(
            id: id,
            name: itemName,
            type: .screenshot,
            fileName: fileName,
            createdAt: Date(),
            collection: collection ?? "Screenshots",
            isFavorite: false,
            cloudShareId: nil
        )

        items.insert(item, at: 0)
        saveManifest()

        libraryLogger.info("📸 Saved screenshot: \(itemName)")
        return item
    }

    /// Save a recording to the library
    func saveRecording(from sourceURL: URL, type: LibraryItem.ItemType = .recording, name: String? = nil, collection: String? = nil) throws -> LibraryItem {
        let id = UUID()
        let itemName = name ?? "Recording_\(formatDate())"
        let ext = sourceURL.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let fileURL = libraryURL.appendingPathComponent(fileName)

        // Copy file
        try fileManager.copyItem(at: sourceURL, to: fileURL)

        // Create item
        let item = LibraryItem(
            id: id,
            name: itemName,
            type: type,
            fileName: fileName,
            createdAt: Date(),
            collection: collection ?? "Recordings",
            isFavorite: false,
            cloudShareId: nil
        )

        items.insert(item, at: 0)
        saveManifest()

        libraryLogger.info("🎬 Saved recording: \(itemName)")
        return item
    }

    // MARK: - Retrieve Items

    /// Get the file URL for an item
    func fileURL(for item: LibraryItem) -> URL {
        libraryURL.appendingPathComponent(item.fileName)
    }

    /// Load image for a library item
    func loadImage(for item: LibraryItem) -> NSImage? {
        let url = fileURL(for: item)
        return NSImage(contentsOf: url)
    }

    /// Get items in a collection
    func items(in collection: String) -> [LibraryItem] {
        if collection == "Favorites" {
            return items.filter { $0.isFavorite }
        } else if collection == "All" || collection == "All Images" {
            return items
        }
        return items.filter { $0.collection == collection }
    }

    /// Get recent items
    func recentItems(limit: Int = 10) -> [LibraryItem] {
        Array(items.prefix(limit))
    }

    // MARK: - Modify Items

    /// Toggle favorite status
    func toggleFavorite(_ item: LibraryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isFavorite.toggle()
            saveManifest()
        }
    }

    /// Move item to collection
    func moveToCollection(_ item: LibraryItem, collection: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].collection = collection
            saveManifest()
        }
    }

    /// Delete item
    func deleteItem(_ item: LibraryItem) {
        let url = fileURL(for: item)
        try? fileManager.removeItem(at: url)
        items.removeAll { $0.id == item.id }
        saveManifest()
        libraryLogger.info("🗑️ Deleted: \(item.name)")
    }

    /// Rename item
    func renameItem(_ item: LibraryItem, to newName: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = LibraryItem(
                id: item.id,
                name: newName,
                type: item.type,
                fileName: item.fileName,
                createdAt: item.createdAt,
                collection: item.collection,
                isFavorite: item.isFavorite,
                cloudShareId: item.cloudShareId
            )
            saveManifest()
        }
    }

    // MARK: - Collections

    /// Add a new collection
    func addCollection(_ name: String) {
        guard !collections.contains(name) else { return }
        collections.append(name)
        saveManifest()
        libraryLogger.info("📁 Added collection: \(name)")
    }

    /// Remove a collection
    func removeCollection(_ name: String) {
        // Don't remove default collections
        guard !["Screenshots", "Recordings", "Favorites"].contains(name) else { return }
        collections.removeAll { $0 == name }
        // Move items to Screenshots
        for i in items.indices where items[i].collection == name {
            items[i].collection = "Screenshots"
        }
        saveManifest()
        libraryLogger.info("🗑️ Removed collection: \(name)")
    }

    /// Rename a collection
    func renameCollection(_ oldName: String, to newName: String) {
        guard !["Screenshots", "Recordings", "Favorites"].contains(oldName) else { return }
        guard !collections.contains(newName) else { return }

        if let index = collections.firstIndex(of: oldName) {
            collections[index] = newName
            // Update items in this collection
            for i in items.indices where items[i].collection == oldName {
                items[i].collection = newName
            }
            saveManifest()
            libraryLogger.info("📁 Renamed collection: \(oldName) → \(newName)")
        }
    }

    // MARK: - Persistence with iCloud Sync

    private func loadManifest() {
        // First try loading from iCloud KV store for quick sync
        if let manifestData = kvStore.data(forKey: "library_manifest"),
           let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: manifestData) {
            // Quick sync from KV store
            mergeManifest(manifest)
        }

        // Then load from file (may have more recent data)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(LibraryManifest.self, from: data)
            mergeManifest(manifest)
        } catch {
            libraryLogger.error("❌ Failed to load manifest: \(error.localizedDescription)")
        }
    }

    private func mergeManifest(_ manifest: LibraryManifest) {
        // Merge items (by ID, keep newest)
        var itemsById: [UUID: LibraryItem] = [:]
        for item in items {
            itemsById[item.id] = item
        }
        for item in manifest.items {
            if let existing = itemsById[item.id] {
                // Keep the newer one
                if item.createdAt > existing.createdAt {
                    itemsById[item.id] = item
                }
            } else {
                itemsById[item.id] = item
            }
        }
        items = Array(itemsById.values).sorted { $0.createdAt > $1.createdAt }

        // Merge collections (union)
        let allCollections = Set(collections).union(Set(manifest.collections))
        collections = ["Screenshots", "Recordings", "Favorites"] +
            allCollections.filter { !["Screenshots", "Recordings", "Favorites"].contains($0) }.sorted()
    }

    private func saveManifest() {
        let manifest = LibraryManifest(items: items, collections: collections)

        do {
            let data = try JSONEncoder().encode(manifest)

            // Save to file
            try data.write(to: manifestURL)

            // Also save to iCloud KV store for quick sync
            kvStore.set(data, forKey: "library_manifest")
            kvStore.synchronize()

            syncStatus = .synced
            libraryLogger.info("💾 Manifest saved, items: \(self.items.count), collections: \(self.collections.count)")
        } catch {
            syncStatus = .error(error.localizedDescription)
            libraryLogger.error("❌ Failed to save manifest: \(error.localizedDescription)")
        }
    }

    private func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    // MARK: - Force Sync

    /// Force sync with iCloud
    func forceSync() {
        syncStatus = .syncing

        // Trigger KV store sync
        kvStore.synchronize()

        // Reload manifest
        loadManifest()

        // Save to ensure consistency
        saveManifest()

        libraryLogger.info("🔄 Force sync completed")
    }

    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Manifest Structure
private struct LibraryManifest: Codable {
    var items: [LibraryItem]
    var collections: [String]
}

// MARK: - Errors
enum LibraryError: LocalizedError {
    case saveFailed
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed: return "Failed to save item to library"
        case .itemNotFound: return "Item not found in library"
        }
    }
}

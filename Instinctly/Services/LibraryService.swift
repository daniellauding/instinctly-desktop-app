import Foundation
import AppKit
import Combine
import os.log

private let libraryLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "LibraryService")

/// Represents an item in the library
struct LibraryItem: Codable, Identifiable {
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
}

/// Service for managing the local library of screenshots and recordings
@MainActor
class LibraryService: ObservableObject {
    static let shared = LibraryService()

    @Published var items: [LibraryItem] = []
    @Published var collections: [String] = ["Screenshots", "Recordings", "Favorites"]

    private let fileManager = FileManager.default
    private var libraryURL: URL
    private var manifestURL: URL

    private init() {
        // Create library folder in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        libraryURL = appSupport.appendingPathComponent("Instinctly/Library", isDirectory: true)
        manifestURL = libraryURL.appendingPathComponent("manifest.json")

        // Create directory if needed
        try? fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        // Load existing items
        loadManifest()

        libraryLogger.info("📚 LibraryService initialized with \(self.items.count) items")
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
        } else if collection == "All" {
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
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(LibraryManifest.self, from: data)
            items = manifest.items
            collections = manifest.collections
        } catch {
            libraryLogger.error("❌ Failed to load manifest: \(error.localizedDescription)")
        }
    }

    private func saveManifest() {
        let manifest = LibraryManifest(items: items, collections: collections)

        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL)
        } catch {
            libraryLogger.error("❌ Failed to save manifest: \(error.localizedDescription)")
        }
    }

    private func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
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

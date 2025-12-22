import Foundation
import CoreData
import CloudKit
import Combine

/// Service for managing iCloud sync with CloudKit
@MainActor
class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    @Published var isCloudAvailable = false

    private var persistentContainer: NSPersistentCloudKitContainer?

    private let container = CKContainer(identifier: "iCloud.com.instinctly.app")

    private init() {
        checkCloudAvailability()
    }

    // MARK: - Setup

    func setupContainer() -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "Instinctly")

        // Configure CloudKit
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to get persistent store description")
        }

        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.instinctly.app"
        )

        // Enable history tracking for sync
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }

        // Enable automatic merging
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )

        self.persistentContainer = container
        return container
    }

    // MARK: - Cloud Availability

    func checkCloudAvailability() {
        Task {
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    switch status {
                    case .available:
                        self.isCloudAvailable = true
                        print("☁️ CloudSync: iCloud available!")
                    case .noAccount:
                        self.isCloudAvailable = false
                        self.syncError = CloudSyncError.noAccount
                        print("⚠️ CloudSync: No iCloud account")
                    case .restricted:
                        self.isCloudAvailable = false
                        self.syncError = CloudSyncError.restricted
                        print("⚠️ CloudSync: iCloud restricted")
                    case .couldNotDetermine:
                        self.isCloudAvailable = false
                        print("⚠️ CloudSync: Could not determine iCloud status")
                    case .temporarilyUnavailable:
                        self.isCloudAvailable = false
                        self.syncError = CloudSyncError.temporarilyUnavailable
                        print("⚠️ CloudSync: iCloud temporarily unavailable")
                    @unknown default:
                        self.isCloudAvailable = false
                        print("⚠️ CloudSync: Unknown iCloud status")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCloudAvailable = false
                    self.syncError = error
                    print("❌ CloudSync: Error checking iCloud: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Sync Operations

    func syncNow() async {
        guard isCloudAvailable else {
            syncError = CloudSyncError.noAccount
            return
        }

        isSyncing = true
        syncError = nil

        do {
            // Trigger sync by saving context
            try persistentContainer?.viewContext.save()

            // Wait a moment for sync to propagate
            try await Task.sleep(nanoseconds: 1_000_000_000)

            lastSyncDate = Date()
        } catch {
            syncError = error
        }

        isSyncing = false
    }

    @objc private func handleRemoteChange(_ notification: Notification) {
        Task { @MainActor in
            lastSyncDate = Date()

            // Notify observers that data has changed
            NotificationCenter.default.post(name: .cloudDataDidChange, object: nil)
        }
    }

    // MARK: - Data Operations

    func saveImage(_ image: InstinctlyImageEntity, context: NSManagedObjectContext) async throws {
        try context.save()

        if isCloudAvailable {
            await syncNow()
        }
    }

    func deleteImage(_ image: InstinctlyImageEntity, context: NSManagedObjectContext) async throws {
        context.delete(image)
        try context.save()

        if isCloudAvailable {
            await syncNow()
        }
    }

    func createCollection(name: String, context: NSManagedObjectContext) async throws -> CollectionEntity {
        let collection = CollectionEntity(context: context)
        collection.id = UUID()
        collection.name = name
        collection.createdAt = Date()
        collection.sortOrder = 0

        try context.save()

        if isCloudAvailable {
            await syncNow()
        }

        return collection
    }
}

// MARK: - Error Types
enum CloudSyncError: LocalizedError {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "No iCloud account configured. Please sign in to iCloud in System Settings."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Please try again later."
        case .syncFailed:
            return "Failed to sync with iCloud."
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let cloudDataDidChange = Notification.Name("cloudDataDidChange")
}

// MARK: - Core Data Entities (Placeholder - would be in .xcdatamodeld)

// These classes represent what would be defined in the Core Data model
// In practice, these are generated from the .xcdatamodeld file

@objc(InstinctlyImageEntity)
class InstinctlyImageEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var name: String?
    @NSManaged var annotationsJSON: String?
    @NSManaged var collection: CollectionEntity?

    var annotations: [Annotation]? {
        get {
            guard let json = annotationsJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([Annotation].self, from: data)
        }
        set {
            guard let annotations = newValue,
                  let data = try? JSONEncoder().encode(annotations) else {
                annotationsJSON = nil
                return
            }
            annotationsJSON = String(data: data, encoding: .utf8)
        }
    }
}

@objc(CollectionEntity)
class CollectionEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var sortOrder: Int32
    @NSManaged var images: NSSet?

    var imagesArray: [InstinctlyImageEntity] {
        (images?.allObjects as? [InstinctlyImageEntity]) ?? []
    }
}

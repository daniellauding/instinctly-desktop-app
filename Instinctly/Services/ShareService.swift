import Foundation
import AppKit
import CloudKit
import SwiftUI
import Combine
import os.log
import CommonCrypto

private let shareLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "ShareService")

/// Service for sharing images and generating shareable links
@MainActor
class ShareService: ObservableObject {
    static let shared = ShareService()

    @Published var isSharing = false
    @Published var shareError: Error?
    @Published var lastSharedURL: URL?
    @Published var isCloudKitAvailable = false

    // Web viewer URL - hosted on GitHub Pages
    private let webViewerBaseURL = "https://daniellauding.github.io/instinctly-share"

    // LAZY CloudKit initialization - only when actually needed for cloud sharing
    private var _container: CKContainer?
    private var _publicDatabase: CKDatabase?

    private var container: CKContainer {
        if _container == nil {
            shareLogger.info("☁️ Lazily initializing CloudKit container...")
            _container = CKContainer(identifier: "iCloud.com.instinctly.app")
        }
        return _container!
    }

    private var publicDatabase: CKDatabase {
        if _publicDatabase == nil {
            _publicDatabase = container.publicCloudDatabase
        }
        return _publicDatabase!
    }

    private init() {
        shareLogger.info("📤 ShareService initialized")
        checkCloudKitAvailability()
    }

    /// Check if CloudKit is available (async, doesn't hang)
    private func checkCloudKitAvailability() {
        Task {
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    isCloudKitAvailable = (status == .available)
                    if isCloudKitAvailable {
                        shareLogger.info("☁️ CloudKit available!")
                    } else {
                        shareLogger.info("⚠️ CloudKit not available: \(String(describing: status))")
                    }
                }
            } catch {
                await MainActor.run {
                    isCloudKitAvailable = false
                    shareLogger.warning("⚠️ CloudKit check failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Share via System Share Sheet

    /// Open macOS share sheet with the image
    func shareViaSystemSheet(image: NSImage, from view: NSView? = nil) {
        shareLogger.info("📤 Opening system share sheet")

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            shareLogger.error("❌ Failed to convert image for sharing")
            return
        }

        // Create temporary file for sharing
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("instinctly_share_\(UUID().uuidString).png")

        do {
            try pngData.write(to: tempURL)

            let picker = NSSharingServicePicker(items: [tempURL])

            if let view = view ?? NSApp.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }

            shareLogger.info("✅ Share sheet displayed")
        } catch {
            shareLogger.error("❌ Failed to create temp file: \(error.localizedDescription)")
            shareError = error
        }
    }

    // MARK: - CloudKit Public Sharing

    /// Upload image to CloudKit public database and get a shareable link
    func uploadAndGetShareableLink(
        image: NSImage,
        title: String = "Shared Screenshot",
        description: String? = nil,
        annotations: [Annotation] = [],
        isPublic: Bool? = nil,
        password: String? = nil,
        allowComments: Bool = false
    ) async throws -> URL {
        shareLogger.info("☁️ Uploading image to CloudKit for sharing...")

        // Check CloudKit availability first
        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available - cannot upload")
            throw ShareError.notAuthenticated
        }

        isSharing = true
        shareError = nil

        defer { isSharing = false }

        // Render annotations onto image if any exist
        let imageToUpload: NSImage
        if !annotations.isEmpty {
            shareLogger.info("🎨 Rendering \(annotations.count) annotations onto image...")
            imageToUpload = ImageProcessingService.renderAnnotations(on: image, annotations: annotations)
        } else {
            imageToUpload = image
        }

        // Convert image to data
        guard let tiffData = imageToUpload.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) else {
            throw ShareError.imageConversionFailed
        }

        shareLogger.info("📦 Image size: \(imageData.count) bytes")

        // Create a unique share ID
        let shareId = UUID().uuidString

        // Save image data to temp file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share_\(shareId).png")
        try imageData.write(to: tempURL)

        // Get user settings
        let username = UserDefaults.standard.string(forKey: "shareUsername") ?? ""
        let defaultPublic = UserDefaults.standard.bool(forKey: "defaultSharePublic")

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: shareId)
        let record = CKRecord(recordType: "SharedImage", recordID: recordID)
        record["title"] = title
        record["createdAt"] = Date()
        record["imageAsset"] = CKAsset(fileURL: tempURL)
        record["mediaType"] = "image"
        record["fileName"] = "\(title).png"

        // Add description if provided
        if let description = description, !description.isEmpty {
            record["description"] = description
        }

        // Add username if set
        if !username.isEmpty {
            record["username"] = username
        }

        // Add visibility
        let visibility = isPublic ?? defaultPublic
        record["isPublic"] = visibility ? 1 : 0

        // Add password protection if set
        if let password = password, !password.isEmpty {
            record["passwordHash"] = hashPassword(password)
        }

        // Add comments setting
        record["allowComments"] = allowComments ? 1 : 0

        // Store annotations as JSON
        if !annotations.isEmpty {
            if let annotationData = try? JSONEncoder().encode(annotations),
               let annotationJSON = String(data: annotationData, encoding: .utf8) {
                record["annotationsJSON"] = annotationJSON
            }
        }

        // Upload to public database
        do {
            let savedRecord = try await publicDatabase.save(record)
            shareLogger.info("✅ Record saved: \(savedRecord.recordID.recordName)")

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            // Generate shareable URL - Web viewer format
            // This URL works in browsers if you host the Web/index.html file
            let shareURL = URL(string: "\(webViewerBaseURL)?id=\(shareId)")!

            // Also store app URL for direct app opening
            let appURL = URL(string: "instinctly://share/\(shareId)")!
            shareLogger.info("🌐 Web URL: \(shareURL.absoluteString)")
            shareLogger.info("📱 App URL: \(appURL.absoluteString)")

            lastSharedURL = shareURL

            return shareURL
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            shareLogger.error("❌ CloudKit upload failed: \(error.localizedDescription)")
            shareError = error
            throw error
        }
    }

    /// Upload file to CloudKit public database and get a shareable link
    func uploadFileAndGetShareableLink(
        fileURL: URL,
        title: String? = nil,
        description: String? = nil,
        collection: String? = nil,
        password: String? = nil,
        isPublic: Bool? = nil,
        allowComments: Bool = false
    ) async throws -> URL {
        shareLogger.info("☁️ Uploading file to CloudKit for sharing: \(fileURL.lastPathComponent)")

        // Check CloudKit availability first
        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available - cannot upload")
            throw ShareError.notAuthenticated
        }

        isSharing = true
        shareError = nil

        defer { isSharing = false }

        // Get user settings
        let username = UserDefaults.standard.string(forKey: "shareUsername") ?? ""
        let defaultPublic = UserDefaults.standard.bool(forKey: "defaultSharePublic")

        // Determine media type from file extension
        let ext = fileURL.pathExtension.lowercased()
        let mediaType: String
        switch ext {
        case "gif":
            mediaType = "gif"
        case "mp4", "mov", "webm":
            mediaType = "video"
        case "m4a", "wav":
            mediaType = "audio"
        case "png", "jpg", "jpeg":
            mediaType = "image"
        case "pdf":
            mediaType = "pdf"
        case "md", "txt":
            mediaType = "text"
        default:
            mediaType = "file"
        }

        // Create a unique share ID
        let shareId = UUID().uuidString

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: shareId)
        let record = CKRecord(recordType: "SharedImage", recordID: recordID)
        record["title"] = title ?? fileURL.lastPathComponent
        record["createdAt"] = Date()
        record["mediaType"] = mediaType
        record["fileName"] = fileURL.lastPathComponent
        record["imageAsset"] = CKAsset(fileURL: fileURL)

        // Add description if provided
        if let description = description, !description.isEmpty {
            record["description"] = description
        }

        // Add username if set
        if !username.isEmpty {
            record["username"] = username
        }

        // Add visibility (use provided value or default from settings)
        let visibility = isPublic ?? defaultPublic
        record["isPublic"] = visibility ? 1 : 0

        // Add collection if provided
        if let collection = collection {
            record["collection"] = collection
        }

        // Add password hash if provided (don't store plain text!)
        if let password = password, !password.isEmpty {
            // Simple hash for demonstration - in production use proper bcrypt or similar
            let passwordHash = hashPassword(password)
            record["passwordHash"] = passwordHash
        }

        // Add comments setting
        record["allowComments"] = allowComments ? 1 : 0

        // Upload to public database
        do {
            let savedRecord = try await publicDatabase.save(record)
            shareLogger.info("✅ Record saved: \(savedRecord.recordID.recordName)")

            // Generate shareable URL - Web viewer format
            let shareURL = URL(string: "\(webViewerBaseURL)?id=\(shareId)")!

            // Also store app URL for direct app opening
            let appURL = URL(string: "instinctly://share/\(shareId)")!
            shareLogger.info("🌐 Web URL: \(shareURL.absoluteString)")
            shareLogger.info("📱 App URL: \(appURL.absoluteString)")

            lastSharedURL = shareURL

            return shareURL
        } catch {
            shareLogger.error("❌ CloudKit upload failed: \(error.localizedDescription)")
            shareError = error
            throw error
        }
    }

    /// Simple password hashing (use bcrypt in production)
    private func hashPassword(_ password: String) -> String {
        // SHA256 hash - good enough for simple protection
        let data = Data(password.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Verify password against stored hash
    func verifyPassword(_ password: String, hash: String) -> Bool {
        return hashPassword(password) == hash
    }

    // MARK: - User Profile

    /// Save or update user profile to CloudKit
    func saveUserProfile(
        username: String,
        bio: String? = nil,
        website: String? = nil,
        logoURL: String? = nil,
        password: String? = nil
    ) async throws {
        shareLogger.info("👤 Saving user profile for: \(username)")

        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available")
            throw ShareError.notAuthenticated
        }

        // Use username as the record ID for easy lookup
        let recordID = CKRecord.ID(recordName: "profile_\(username)")

        // Try to fetch existing record or create new one
        var record: CKRecord
        do {
            record = try await publicDatabase.record(for: recordID)
            shareLogger.info("📝 Updating existing profile")
        } catch {
            record = CKRecord(recordType: "UserProfile", recordID: recordID)
            shareLogger.info("🆕 Creating new profile")
        }

        // Set profile fields
        record["username"] = username
        record["bio"] = bio
        record["website"] = website
        record["logoURL"] = logoURL
        record["updatedAt"] = Date()

        // Hash password if provided
        if let password = password, !password.isEmpty {
            record["passwordHash"] = hashPassword(password)
        } else {
            record["passwordHash"] = nil
        }

        // Save to CloudKit
        do {
            let savedRecord = try await publicDatabase.save(record)
            shareLogger.info("✅ Profile saved: \(savedRecord.recordID.recordName)")
        } catch {
            shareLogger.error("❌ Failed to save profile: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch user profile from CloudKit
    func fetchUserProfile(username: String) async throws -> (bio: String?, website: String?, logoURL: String?, hasPassword: Bool) {
        shareLogger.info("👤 Fetching profile for: \(username)")

        let recordID = CKRecord.ID(recordName: "profile_\(username)")

        do {
            let record = try await publicDatabase.record(for: recordID)

            let bio = record["bio"] as? String
            let website = record["website"] as? String
            let logoURL = record["logoURL"] as? String
            let hasPassword = (record["passwordHash"] as? String) != nil

            shareLogger.info("✅ Profile fetched for \(username)")
            return (bio, website, logoURL, hasPassword)
        } catch {
            // Profile doesn't exist yet - that's okay
            shareLogger.info("ℹ️ No profile found for \(username)")
            return (nil, nil, nil, false)
        }
    }

    // MARK: - Collections

    /// Save or update a collection to CloudKit
    func saveCollection(
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
        password: String? = nil
    ) async throws {
        let username = UserDefaults.standard.string(forKey: "shareUsername") ?? ""
        shareLogger.info("📁 Saving collection: \(name) for user: \(username)")

        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available")
            throw ShareError.notAuthenticated
        }

        // Create unique record ID using username and collection name
        let sanitizedName = name.replacingOccurrences(of: " ", with: "_").lowercased()
        let recordID = CKRecord.ID(recordName: "collection_\(username)_\(sanitizedName)")

        // Try to fetch existing record or create new one
        var record: CKRecord
        do {
            record = try await publicDatabase.record(for: recordID)
            shareLogger.info("📝 Updating existing collection")
        } catch {
            record = CKRecord(recordType: "Collection", recordID: recordID)
            shareLogger.info("🆕 Creating new collection")
        }

        // Set collection fields
        record["name"] = name
        record["username"] = username
        record["description"] = description
        record["isPublic"] = isPublic ? 1 : 0
        record["updatedAt"] = Date()
        record["createdAt"] = record["createdAt"] ?? Date()

        // Hash password if provided
        if let password = password, !password.isEmpty {
            record["passwordHash"] = hashPassword(password)
        } else {
            record["passwordHash"] = nil
        }

        // Save to CloudKit
        do {
            let savedRecord = try await publicDatabase.save(record)
            shareLogger.info("✅ Collection saved: \(savedRecord.recordID.recordName)")
        } catch {
            shareLogger.error("❌ Failed to save collection: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch a collection from CloudKit
    func fetchCollection(username: String, collectionName: String) async throws -> (name: String, description: String?, hasPassword: Bool, isPublic: Bool) {
        let sanitizedName = collectionName.replacingOccurrences(of: " ", with: "_").lowercased()
        shareLogger.info("📁 Fetching collection: \(collectionName) for user: \(username)")

        let recordID = CKRecord.ID(recordName: "collection_\(username)_\(sanitizedName)")

        do {
            let record = try await publicDatabase.record(for: recordID)

            let name = record["name"] as? String ?? collectionName
            let description = record["description"] as? String
            let hasPassword = (record["passwordHash"] as? String) != nil
            let isPublic = (record["isPublic"] as? Int ?? 0) == 1

            shareLogger.info("✅ Collection fetched: \(name)")
            return (name, description, hasPassword, isPublic)
        } catch {
            shareLogger.error("❌ Collection not found: \(collectionName)")
            throw error
        }
    }

    /// Fetch items in a public collection
    func fetchCollectionItems(username: String, collectionName: String) async throws -> [(recordID: String, title: String, fileName: String, mediaType: String, viewCount: Int, hasPassword: Bool)] {
        shareLogger.info("📁 Fetching items in collection: \(collectionName)")

        guard isCloudKitAvailable else {
            throw ShareError.notAuthenticated
        }

        let query = CKQuery(recordType: "SharedImage", predicate: NSPredicate(format: "username == %@ AND collection == %@", username, collectionName))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let (results, _) = try await publicDatabase.records(matching: query)

            var items: [(recordID: String, title: String, fileName: String, mediaType: String, viewCount: Int, hasPassword: Bool)] = []

            for (recordID, result) in results {
                if case .success(let record) = result {
                    let title = record["title"] as? String ?? "Untitled"
                    let fileName = record["fileName"] as? String ?? ""
                    let mediaType = record["mediaType"] as? String ?? "image"
                    let viewCount = record["viewCount"] as? Int ?? 0
                    let hasPassword = (record["passwordHash"] as? String) != nil

                    items.append((recordID.recordName, title, fileName, mediaType, viewCount, hasPassword))
                }
            }

            shareLogger.info("✅ Fetched \(items.count) items in collection")
            return items
        } catch {
            shareLogger.error("❌ Failed to fetch collection items: \(error)")
            throw error
        }
    }

    // MARK: - Fetch Shared Image

    /// Fetch a shared image by its share ID
    func fetchSharedImage(shareId: String) async throws -> (image: NSImage, annotations: [Annotation]) {
        shareLogger.info("📥 Fetching shared image: \(shareId)")

        let recordID = CKRecord.ID(recordName: shareId)

        do {
            let record = try await publicDatabase.record(for: recordID)

            guard let asset = record["imageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let image = NSImage(contentsOf: fileURL) else {
                throw ShareError.imageNotFound
            }

            var annotations: [Annotation] = []
            if let annotationJSON = record["annotationsJSON"] as? String,
               let data = annotationJSON.data(using: .utf8) {
                annotations = (try? JSONDecoder().decode([Annotation].self, from: data)) ?? []
            }

            shareLogger.info("✅ Fetched shared image with \(annotations.count) annotations")
            return (image, annotations)
        } catch {
            shareLogger.error("❌ Failed to fetch shared image: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Fetch shared media by its share ID
    func fetchSharedMedia(shareId: String) async throws -> (fileURL: URL, mediaType: String, fileName: String) {
        shareLogger.info("📥 Fetching shared media: \(shareId)")
        
        let recordID = CKRecord.ID(recordName: shareId)
        
        do {
            let record = try await publicDatabase.record(for: recordID)
            
            guard let asset = record["imageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let mediaType = record["mediaType"] as? String,
                  let fileName = record["fileName"] as? String else {
                throw ShareError.imageNotFound
            }
            
            shareLogger.info("✅ Fetched shared media: \(fileName)")
            return (fileURL, mediaType, fileName)
        } catch {
            shareLogger.error("❌ Failed to fetch shared media: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch all shared media from CloudKit for management
    func fetchAllSharedMedia() async throws -> [(recordID: String, title: String, fileName: String, mediaType: String, createdAt: Date, collection: String?, viewCount: Int, hasPassword: Bool)] {
        shareLogger.info("📥 Fetching all shared media from CloudKit...")

        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available")
            throw ShareError.notAuthenticated
        }

        // Use a simple predicate that doesn't reference record fields that aren't queryable
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "SharedImage", predicate: predicate)

        // No server-side sorting to avoid index issues - sort client-side instead

        do {
            let result = try await publicDatabase.records(matching: query)
            var sharedMedia: [(recordID: String, title: String, fileName: String, mediaType: String, createdAt: Date, collection: String?, viewCount: Int, hasPassword: Bool)] = []

            for (recordID, recordResult) in result.matchResults {
                switch recordResult {
                case .success(let record):
                    let title = record["title"] as? String ?? "Untitled"
                    let fileName = record["fileName"] as? String ?? title
                    let mediaType = record["mediaType"] as? String ?? "image"
                    let createdAt = record.creationDate ?? Date()
                    let collection = record["collection"] as? String
                    let viewCount = record["viewCount"] as? Int ?? 0
                    let hasPassword = (record["passwordHash"] as? String) != nil

                    sharedMedia.append((
                        recordID: recordID.recordName,
                        title: title,
                        fileName: fileName,
                        mediaType: mediaType,
                        createdAt: createdAt,
                        collection: collection,
                        viewCount: viewCount,
                        hasPassword: hasPassword
                    ))
                case .failure(let error):
                    shareLogger.warning("⚠️ Failed to process record \(recordID): \(error)")
                }
            }

            // Sort client-side by createdAt (newest first)
            sharedMedia.sort { $0.createdAt > $1.createdAt }

            shareLogger.info("✅ Fetched \(sharedMedia.count) shared media items")
            return sharedMedia
        } catch {
            shareLogger.error("❌ Failed to fetch shared media: \(error)")
            throw error
        }
    }

    /// Increment view count for a shared item (called from web viewer)
    func incrementViewCount(shareId: String) async throws {
        shareLogger.info("👁️ Incrementing view count for: \(shareId)")

        let recordID = CKRecord.ID(recordName: shareId)

        do {
            let record = try await publicDatabase.record(for: recordID)
            let currentCount = record["viewCount"] as? Int ?? 0
            record["viewCount"] = currentCount + 1

            _ = try await publicDatabase.save(record)
            shareLogger.info("✅ View count incremented to \(currentCount + 1)")
        } catch {
            shareLogger.warning("⚠️ Failed to increment view count: \(error)")
            // Don't throw - view counting is not critical
        }
    }
    
    /// Delete shared media from CloudKit
    func deleteSharedMedia(recordID: String) async throws {
        shareLogger.info("🗑️ Deleting shared media: \(recordID)")

        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available")
            throw ShareError.notAuthenticated
        }

        let ckRecordID = CKRecord.ID(recordName: recordID)

        do {
            _ = try await publicDatabase.deleteRecord(withID: ckRecordID)
            shareLogger.info("✅ Successfully deleted shared media: \(recordID)")
        } catch {
            shareLogger.error("❌ Failed to delete shared media: \(error)")
            throw error
        }
    }

    /// Update shared media settings in CloudKit
    func updateSharedMedia(
        recordID: String,
        title: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil,
        password: String? = nil,
        removePassword: Bool = false
    ) async throws {
        shareLogger.info("📝 Updating shared media: \(recordID)")

        guard isCloudKitAvailable else {
            shareLogger.error("❌ CloudKit not available")
            throw ShareError.notAuthenticated
        }

        let ckRecordID = CKRecord.ID(recordName: recordID)

        // Fetch existing record
        let record = try await publicDatabase.record(for: ckRecordID)

        // Update fields
        if let title = title {
            record["title"] = title
        }
        if let description = description {
            record["description"] = description
        }
        if let isPublic = isPublic {
            record["isPublic"] = isPublic ? 1 : 0
        }
        if removePassword {
            record["passwordHash"] = nil
        } else if let password = password, !password.isEmpty {
            record["passwordHash"] = hashPassword(password)
        }

        // Save updated record
        do {
            _ = try await publicDatabase.save(record)
            shareLogger.info("✅ Successfully updated shared media: \(recordID)")
        } catch {
            shareLogger.error("❌ Failed to update shared media: \(error)")
            throw error
        }
    }

    // MARK: - Copy Link to Clipboard

    /// Copy the shareable link to clipboard
    func copyLinkToClipboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        shareLogger.info("📋 Link copied to clipboard")
    }

    // MARK: - Quick Share (Copy image to clipboard)

    /// Copy image to clipboard for quick paste
    func copyImageToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        shareLogger.info("📋 Image copied to clipboard")
    }

    // MARK: - Export and Share

    /// Export image with annotations rendered and share
    func exportAndShare(
        image: NSImage,
        annotations: [Annotation],
        format: ExportFormat = .png
    ) async throws -> URL {
        shareLogger.info("📤 Exporting with \(annotations.count) annotations")

        // Render annotations onto image
        let renderedImage = ImageProcessingService.renderAnnotations(on: image, annotations: annotations)

        // Export to file
        let fileName = "Instinctly_\(Date().formatted(.dateTime.year().month().day().hour().minute().second())).png"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(fileName)

        guard let data = format == .png
                ? ImageProcessingService.exportAsPNG(renderedImage)
                : ImageProcessingService.exportAsJPEG(renderedImage) else {
            throw ShareError.exportFailed
        }

        try data.write(to: fileURL)
        shareLogger.info("✅ Exported to: \(fileURL.path)")

        return fileURL
    }

    // MARK: - Save to Downloads

    func saveToDownloads(image: NSImage, annotations: [Annotation] = []) async throws -> URL {
        let renderedImage = annotations.isEmpty ? image : ImageProcessingService.renderAnnotations(on: image, annotations: annotations)

        let fileName = "Instinctly_\(formatDateForFilename()).png"
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(fileName)

        guard let data = ImageProcessingService.exportAsPNG(renderedImage) else {
            throw ShareError.exportFailed
        }

        try data.write(to: fileURL)
        shareLogger.info("✅ Saved to Downloads: \(fileURL.path)")

        // Reveal in Finder
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")

        return fileURL
    }

    private func formatDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Export Format
enum ExportFormat: String, CaseIterable {
    case png = "PNG"
    case jpeg = "JPEG"
    case pdf = "PDF"
}

// MARK: - Share Errors
enum ShareError: LocalizedError {
    case imageConversionFailed
    case uploadFailed
    case imageNotFound
    case exportFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image for sharing"
        case .uploadFailed:
            return "Failed to upload image"
        case .imageNotFound:
            return "Shared image not found"
        case .exportFailed:
            return "Failed to export image"
        case .notAuthenticated:
            return "Please sign in to iCloud to share images"
        }
    }
}

// MARK: - Share Sheet View
struct ShareSheet: View {
    let image: NSImage
    let annotations: [Annotation]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shareService = ShareService.shared

    @State private var shareURL: URL?
    @State private var shareId: String?
    @State private var isUploading = false
    @State private var isUpdating = false
    @State private var isDeleting = false
    @State private var isEditing = false
    @State private var showCopiedAlert = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var shareTitle = ""
    @State private var shareDescription = ""
    @State private var sharePassword = ""
    @State private var hasExistingPassword = false
    @State private var removePassword = false
    @State private var isPublic = false
    @State private var allowComments = false
    @AppStorage("defaultSharePublic") private var defaultSharePublic = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Share Screenshot")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }

            // Preview
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .cornerRadius(8)
                .shadow(radius: 2)

            // Quick Actions
            HStack(spacing: 16) {
                ShareActionButton(
                    icon: "doc.on.clipboard",
                    title: "Copy Image",
                    color: .blue
                ) {
                    shareService.copyImageToClipboard(image)
                    showCopiedAlert = true
                }

                ShareActionButton(
                    icon: "square.and.arrow.down",
                    title: "Save",
                    color: .green
                ) {
                    Task {
                        try? await shareService.saveToDownloads(image: image, annotations: annotations)
                    }
                }

                ShareActionButton(
                    icon: "square.and.arrow.up",
                    title: "Share...",
                    color: .orange
                ) {
                    shareService.shareViaSystemSheet(image: image)
                }
            }

            Divider()

            // Cloud Sharing (requires iCloud setup)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Cloud Sharing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Beta")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }

                if let url = shareURL, !isEditing {
                    // Share link display
                    HStack {
                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            shareService.copyLinkToClipboard(url)
                            showCopiedAlert = true
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                    // Status badges
                    HStack(spacing: 8) {
                        if isPublic {
                            Label("Public", systemImage: "globe")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Label("Private", systemImage: "lock.shield")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if hasExistingPassword || !sharePassword.isEmpty {
                            Label("Protected", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit Settings", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            if isDeleting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Label("Delete Link", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDeleting)
                    }
                    .padding(.top, 4)

                } else if isEditing {
                    // Edit mode - show form to update settings
                    Text("Edit Share Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Title", text: $shareTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    TextField("Description", text: $shareDescription)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    // Password section
                    VStack(alignment: .leading, spacing: 4) {
                        if hasExistingPassword {
                            HStack {
                                Toggle("Remove password protection", isOn: $removePassword)
                                    .font(.caption)
                            }
                        }
                        if !removePassword {
                            HStack {
                                SecureField(hasExistingPassword ? "New password (leave empty to keep)" : "Password (optional)", text: $sharePassword)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                if !sharePassword.isEmpty {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    Toggle("Make public (visible on profile)", isOn: $isPublic)
                        .font(.caption)

                    Toggle("Allow comments", isOn: $allowComments)
                        .font(.caption)

                    HStack(spacing: 12) {
                        Button {
                            isEditing = false
                            removePassword = false
                            sharePassword = ""
                        } label: {
                            Text("Cancel")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            updateShare()
                        } label: {
                            if isUpdating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Save Changes")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isUpdating)
                    }
                } else {
                    // Title field
                    TextField("Title (optional)", text: $shareTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    // Description field
                    TextField("Description (optional)", text: $shareDescription)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    // Password field
                    HStack {
                        SecureField("Password (optional)", text: $sharePassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        if !sharePassword.isEmpty {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }

                    // Public toggle
                    Toggle("Make public (visible on profile)", isOn: $isPublic)
                        .font(.caption)

                    // Comments toggle
                    Toggle("Allow comments", isOn: $allowComments)
                        .font(.caption)

                    Button {
                        uploadToCloud()
                    } label: {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "link.badge.plus")
                            }
                            Text(isUploading ? "Uploading..." : "Generate Shareable Link")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploading)
                }

                if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("Tip: Use 'Copy Image' or 'Save' for local sharing")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert("Delete Share Link?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteShare()
            }
        } message: {
            Text("This will permanently remove the shareable link. Anyone with the link will no longer be able to access this content.")
        }
        .onAppear {
            isPublic = defaultSharePublic
        }
    }

    private func uploadToCloud() {
        isUploading = true
        errorMessage = nil

        Task {
            do {
                let url = try await shareService.uploadAndGetShareableLink(
                    image: image,
                    title: shareTitle.isEmpty ? "Shared Screenshot" : shareTitle,
                    description: shareDescription.isEmpty ? nil : shareDescription,
                    annotations: annotations,
                    isPublic: isPublic,
                    password: sharePassword.isEmpty ? nil : sharePassword,
                    allowComments: allowComments
                )
                shareURL = url
                // Extract share ID from URL
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let idParam = components.queryItems?.first(where: { $0.name == "id" })?.value {
                    shareId = idParam
                }
                // Track if password was set
                if !sharePassword.isEmpty {
                    hasExistingPassword = true
                }
                sharePassword = "" // Clear password after upload
            } catch let ckError as CKError {
                // Handle specific CloudKit errors
                switch ckError.code {
                case .notAuthenticated:
                    errorMessage = "Please sign in to iCloud in System Settings"
                case .networkFailure, .networkUnavailable:
                    errorMessage = "No internet connection"
                case .quotaExceeded:
                    errorMessage = "iCloud storage full"
                default:
                    errorMessage = "CloudKit error: \(ckError.localizedDescription)"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isUploading = false
        }
    }

    private func updateShare() {
        guard let shareId = shareId else { return }
        isUpdating = true
        errorMessage = nil

        Task {
            do {
                try await shareService.updateSharedMedia(
                    recordID: shareId,
                    title: shareTitle.isEmpty ? nil : shareTitle,
                    description: shareDescription.isEmpty ? nil : shareDescription,
                    isPublic: isPublic,
                    password: sharePassword.isEmpty ? nil : sharePassword,
                    removePassword: removePassword
                )
                // Update password state
                if removePassword {
                    hasExistingPassword = false
                } else if !sharePassword.isEmpty {
                    hasExistingPassword = true
                }
                sharePassword = ""
                removePassword = false
                isEditing = false
            } catch {
                errorMessage = "Failed to update: \(error.localizedDescription)"
            }
            isUpdating = false
        }
    }

    private func deleteShare() {
        guard let shareId = shareId else { return }
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                try await shareService.deleteSharedMedia(recordID: shareId)
                // Reset state
                shareURL = nil
                self.shareId = nil
                hasExistingPassword = false
                sharePassword = ""
                shareTitle = ""
                shareDescription = ""
            } catch {
                errorMessage = "Failed to delete: \(error.localizedDescription)"
            }
            isDeleting = false
        }
    }
}

// MARK: - Share Action Button
struct ShareActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(width: 80, height: 70)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ShareSheet(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        annotations: []
    )
}

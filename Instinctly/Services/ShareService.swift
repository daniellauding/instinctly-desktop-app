import Foundation
import AppKit
import CloudKit
import SwiftUI
import os.log

private nonisolated(unsafe) let shareLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "ShareService")

/// Service for sharing images and generating shareable links
@MainActor
class ShareService: ObservableObject {
    static let shared = ShareService()

    @Published var isSharing = false
    @Published var shareError: Error?
    @Published var lastSharedURL: URL?

    private let container = CKContainer(identifier: "iCloud.com.instinctly.app")
    private let publicDatabase: CKDatabase

    private init() {
        publicDatabase = container.publicCloudDatabase
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
        annotations: [Annotation] = []
    ) async throws -> URL {
        shareLogger.info("☁️ Uploading image to CloudKit for sharing...")
        isSharing = true
        shareError = nil

        defer { isSharing = false }

        // Convert image to data
        guard let tiffData = image.tiffRepresentation,
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

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: shareId)
        let record = CKRecord(recordType: "SharedImage", recordID: recordID)
        record["title"] = title
        record["createdAt"] = Date()
        record["imageAsset"] = CKAsset(fileURL: tempURL)

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

            // Generate shareable URL
            // Format: instinctly://share/{shareId} or a web URL if you have a web viewer
            let shareURL = URL(string: "instinctly://share/\(shareId)")!

            // Also create a CloudKit share URL for web access
            // This requires setting up a CloudKit web service
            // For now, we'll use a custom URL scheme + clipboard

            lastSharedURL = shareURL
            shareLogger.info("🔗 Share URL: \(shareURL.absoluteString)")

            return shareURL
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            shareLogger.error("❌ CloudKit upload failed: \(error.localizedDescription)")
            shareError = error
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
    @State private var isUploading = false
    @State private var showCopiedAlert = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
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

            // Cloud Sharing
            VStack(alignment: .leading, spacing: 12) {
                Text("Cloud Sharing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let url = shareURL {
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
                } else {
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
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private func uploadToCloud() {
        isUploading = true
        errorMessage = nil

        Task {
            do {
                let url = try await shareService.uploadAndGetShareableLink(
                    image: image,
                    annotations: annotations
                )
                shareURL = url
            } catch {
                errorMessage = error.localizedDescription
            }
            isUploading = false
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

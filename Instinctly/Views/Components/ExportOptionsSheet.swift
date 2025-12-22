import SwiftUI
import UniformTypeIdentifiers

struct ExportOptionsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var libraryService = LibraryService.shared

    @State private var selectedFormat: ExportFormat = .png
    @State private var jpegQuality: Double = 0.9
    @State private var includeAnnotations: Bool = true
    @State private var selectedCollection: String? = nil
    @State private var isExporting = false
    @State private var showSavedAlert = false

    enum ExportFormat: String, CaseIterable {
        case png = "PNG"
        case jpeg = "JPEG"
        case pdf = "PDF"

        var fileExtension: String {
            rawValue.lowercased()
        }

        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .pdf: return .pdf
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Image")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                // Format Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // JPEG Quality (only shown for JPEG)
                if selectedFormat == .jpeg {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Quality")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(jpegQuality * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                    }
                }

                // Include Annotations
                Toggle("Include annotations", isOn: $includeAnnotations)
                    .toggleStyle(.checkbox)

                Divider()

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        QuickActionButton(
                            title: "Copy",
                            icon: "doc.on.doc",
                            action: copyToClipboard
                        )

                        QuickActionButton(
                            title: "Save to Desktop",
                            icon: "desktopcomputer",
                            action: saveToDesktop
                        )

                        QuickActionButton(
                            title: "Share",
                            icon: "square.and.arrow.up",
                            action: share
                        )
                    }
                }

                Divider()

                // Save to Collection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save to Library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Menu {
                        ForEach(libraryService.collections, id: \.self) { collection in
                            Button(collection) { selectedCollection = collection }
                        }
                        Divider()
                        Button("New Collection...") { createNewCollection() }
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                            Text(selectedCollection ?? "Select collection...")
                                .foregroundColor(selectedCollection == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if let collection = selectedCollection {
                    Button("Save to \(collection)") {
                        saveToCollection()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Save As...") {
                    saveAs()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400)
        .alert("Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Image saved to \(selectedCollection ?? "library")")
        }
    }

    // MARK: - Actions

    private func getExportImage() -> NSImage? {
        guard let image = appState.currentImage else { return nil }

        if includeAnnotations {
            return ImageProcessingService.renderAnnotations(on: image, annotations: appState.annotations)
        } else {
            return image
        }
    }

    private func copyToClipboard() {
        guard let image = getExportImage() else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        dismiss()
    }

    private func saveToDesktop() {
        guard let image = getExportImage() else { return }

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileName = "Instinctly_\(formattedDate()).\(selectedFormat.fileExtension)"
        let fileURL = desktopURL.appendingPathComponent(fileName)

        saveImage(image, to: fileURL)
        dismiss()
    }

    private func saveAs() {
        guard let image = getExportImage() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [selectedFormat.utType]
        panel.nameFieldStringValue = "Instinctly_\(formattedDate()).\(selectedFormat.fileExtension)"
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                saveImage(image, to: url)
            }
            dismiss()
        }
    }

    private func saveImage(_ image: NSImage, to url: URL) {
        let data: Data?

        switch selectedFormat {
        case .png:
            data = ImageProcessingService.exportAsPNG(image)
        case .jpeg:
            data = ImageProcessingService.exportAsJPEG(image, quality: jpegQuality)
        case .pdf:
            data = ImageProcessingService.exportAsPDF(image)
        }

        if let data = data {
            try? data.write(to: url)
        }
    }

    private func share() {
        guard let image = getExportImage() else { return }

        let _ = NSSharingServicePicker(items: [image])
        // Note: In a real implementation, you'd need to present this relative to a view
    }

    private func saveToCollection() {
        guard let image = getExportImage(),
              let collection = selectedCollection else { return }

        do {
            _ = try libraryService.saveScreenshot(image, collection: collection)
            showSavedAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
            }
        } catch {
            print("❌ Failed to save to library: \(error)")
        }
    }

    private func createNewCollection() {
        // For now, add a generic new collection
        let newName = "Collection \(libraryService.collections.count + 1)"
        libraryService.addCollection(newName)
        selectedCollection = newName
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ExportOptionsSheet()
        .environmentObject(AppState.shared)
}

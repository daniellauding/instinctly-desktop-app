import SwiftUI
import ScreenCaptureKit
import AppKit

struct WindowPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [SCWindow] = []
    @State private var selectedWindow: SCWindow?
    @State private var isLoading = true

    let onSelect: (SCWindow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Window")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Window list
            if isLoading {
                Spacer()
                ProgressView("Loading windows...")
                Spacer()
            } else if windows.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No windows available")
                        .font(.headline)
                    Text("Open some applications to capture their windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                        ForEach(windows, id: \.windowID) { window in
                            WindowThumbnailCard(
                                window: window,
                                isSelected: selectedWindow?.windowID == window.windowID,
                                onTap: {
                                    selectedWindow = window
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Capture") {
                    if let window = selectedWindow {
                        dismiss()
                        onSelect(window)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWindow == nil)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 600, height: 450)
        .task {
            await loadWindows()
        }
    }

    private func loadWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            await MainActor.run {
                windows = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier &&
                    $0.frame.width > 100 && $0.frame.height > 100 &&
                    $0.title != nil && !($0.title?.isEmpty ?? true)
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

struct WindowThumbnailCard: View {
    let window: SCWindow
    let isSelected: Bool
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16/10, contentMode: .fit)

                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(6)
                            .padding(4)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                // App info
                VStack(spacing: 2) {
                    Text(window.title ?? "Unknown")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let appName = window.owningApplication?.applicationName {
                        Text(appName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .task {
            await captureThumbnail()
        }
    }

    private func captureThumbnail() async {
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = 300
            config.height = 200
            config.scalesToFit = true
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            await MainActor.run {
                thumbnail = NSImage(cgImage: image, size: CGSize(width: 300, height: 200))
            }
        } catch {
            // Thumbnail capture failed, show placeholder
        }
    }
}

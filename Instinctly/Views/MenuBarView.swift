import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var captureService = ScreenCaptureService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Instinctly")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if !captureService.isAuthorized {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .help("Screen capture permission required")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Quick Actions
            VStack(spacing: 2) {
                MenuButton(
                    title: "Capture Region",
                    icon: "rectangle.dashed",
                    shortcut: "3"
                ) {
                    captureRegion()
                }

                MenuButton(
                    title: "Capture Window",
                    icon: "macwindow",
                    shortcut: "4"
                ) {
                    captureWindow()
                }

                MenuButton(
                    title: "Capture Full Screen",
                    icon: "rectangle.on.rectangle",
                    shortcut: "5"
                ) {
                    captureFullScreen()
                }

                MenuButton(
                    title: "Open from Clipboard",
                    icon: "doc.on.clipboard",
                    shortcut: "6"
                ) {
                    openFromClipboard()
                }
            }
            .padding(.vertical, 8)

            Divider()

            // Recording Section
            VStack(spacing: 2) {
                MenuBarRecordingButton()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .padding(.vertical, 4)

            Divider()

            // Recent Captures (placeholder)
            if !recentCaptures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(recentCaptures.prefix(3), id: \.self) { capture in
                        RecentCaptureRow(capture: capture)
                    }
                }
                .padding(.bottom, 8)

                Divider()
            }

            // Bottom Actions
            VStack(spacing: 2) {
                MenuButton(
                    title: "Collections",
                    icon: "folder",
                    shortcut: nil
                ) {
                    openWindow(id: "collections")
                }

                MenuButton(
                    title: "Settings...",
                    icon: "gear",
                    shortcut: ","
                ) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            .padding(.vertical, 8)

            Divider()

            // Quit
            Button(action: { NSApp.terminate(nil) }) {
                HStack {
                    Text("Quit Instinctly")
                    Spacer()
                    Text("Q")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280)
    }

    // MARK: - Placeholder Data
    private var recentCaptures: [String] {
        [] // Will be populated from Core Data
    }

    // MARK: - Actions

    private func captureRegion() {
        Task {
            do {
                let image = try await captureService.captureRegion()
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                    openWindow(id: "editor", value: UUID())
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func captureWindow() {
        Task {
            do {
                let image = try await captureService.captureWindow()
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                    openWindow(id: "editor", value: UUID())
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func captureFullScreen() {
        Task {
            do {
                let image = try await captureService.captureFullScreen()
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                    openWindow(id: "editor", value: UUID())
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func openFromClipboard() {
        if let data = NSPasteboard.general.data(forType: .tiff),
           let image = NSImage(data: data) {
            appState.currentImage = image
            appState.annotations = []
            openWindow(id: "editor", value: UUID())
        } else if let data = NSPasteboard.general.data(forType: .png),
                  let image = NSImage(data: data) {
            appState.currentImage = image
            appState.annotations = []
            openWindow(id: "editor", value: UUID())
        }
    }
}

// MARK: - Menu Button
struct MenuButton: View {
    let title: String
    let icon: String
    let shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.primary)

                Text(title)
                    .foregroundColor(.primary)

                Spacer()

                if let shortcut = shortcut {
                    Text("⌘⇧\(shortcut)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Recent Capture Row
struct RecentCaptureRow: View {
    let capture: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(capture)
                    .font(.caption)
                    .lineLimit(1)
                Text("Just now")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}

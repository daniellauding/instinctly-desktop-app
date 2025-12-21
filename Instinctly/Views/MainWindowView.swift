import SwiftUI
import ScreenCaptureKit

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var captureService = ScreenCaptureService()
    @State private var showWindowPicker = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("Quick Actions") {
                    Button(action: captureRegion) {
                        Label("Capture Region", systemImage: "rectangle.dashed")
                    }

                    Button(action: captureWindow) {
                        Label("Capture Window", systemImage: "macwindow")
                    }

                    Button(action: captureFullScreen) {
                        Label("Capture Full Screen", systemImage: "rectangle.on.rectangle")
                    }

                    Button(action: openFromClipboard) {
                        Label("Open from Clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                Section("Library") {
                    NavigationLink(value: "all") {
                        Label("All Images", systemImage: "photo.on.rectangle")
                    }

                    NavigationLink(value: "screenshots") {
                        Label("Screenshots", systemImage: "camera.viewfinder")
                    }

                    NavigationLink(value: "favorites") {
                        Label("Favorites", systemImage: "star")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            // Main content
            VStack(spacing: 0) {
                if appState.currentImage != nil {
                    // Show editor if image is loaded
                    ImageEditorView(imageId: nil)
                } else {
                    // Welcome/empty state
                    WelcomeView(
                        onCaptureRegion: captureRegion,
                        onCaptureWindow: captureWindow,
                        onCaptureFullScreen: captureFullScreen,
                        onOpenFromClipboard: openFromClipboard
                    )
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: captureRegion) {
                    Label("Capture", systemImage: "camera.viewfinder")
                }
                .help("Capture Region (⌘⇧4)")
            }
        }
        .sheet(isPresented: $showWindowPicker) {
            WindowPickerView { selectedWindow in
                captureSelectedWindow(selectedWindow)
            }
        }
    }

    // MARK: - Actions

    private func captureRegion() {
        Task {
            do {
                let image = try await captureService.captureRegion()
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    private func captureWindow() {
        showWindowPicker = true
    }

    private func captureSelectedWindow(_ window: SCWindow) {
        Task {
            do {
                let image = try await captureService.captureWindow(window)
                await MainActor.run {
                    appState.currentImage = image
                    appState.annotations = []
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
        } else if let data = NSPasteboard.general.data(forType: .png),
                  let image = NSImage(data: data) {
            appState.currentImage = image
            appState.annotations = []
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    let onCaptureRegion: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureFullScreen: () -> Void
    let onOpenFromClipboard: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/logo
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Welcome to Instinctly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Capture, annotate, and share screenshots")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Quick action buttons
            HStack(spacing: 20) {
                QuickActionCard(
                    title: "Capture Region",
                    subtitle: "⌘⇧3",
                    icon: "rectangle.dashed",
                    action: onCaptureRegion
                )

                QuickActionCard(
                    title: "Capture Window",
                    subtitle: "⌘⇧4",
                    icon: "macwindow",
                    action: onCaptureWindow
                )

                QuickActionCard(
                    title: "Full Screen",
                    subtitle: "⌘⇧5",
                    icon: "rectangle.on.rectangle",
                    action: onCaptureFullScreen
                )

                QuickActionCard(
                    title: "From Clipboard",
                    subtitle: "⌘⇧6",
                    icon: "doc.on.clipboard",
                    action: onOpenFromClipboard
                )
            }
            .padding(.top, 20)

            Spacer()

            // Keyboard shortcuts hint
            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                Text("Use global keyboard shortcuts to capture from anywhere")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isHovered ? .primary : .secondary)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppState.shared)
        .frame(width: 900, height: 600)
}

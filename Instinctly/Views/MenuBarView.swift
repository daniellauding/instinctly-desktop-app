import SwiftUI
import ScreenCaptureKit

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
                RecordingMenuButton(
                    title: "Record Region",
                    icon: "rectangle.dashed.badge.record",
                    mode: .region
                )

                RecordingMenuButton(
                    title: "Record Window",
                    icon: "macwindow.badge.plus",
                    mode: .window
                )

                RecordingMenuButton(
                    title: "Record Full Screen",
                    icon: "rectangle.on.rectangle",
                    mode: .fullScreen
                )

                RecordingMenuButton(
                    title: "Record GIF",
                    icon: "photo.stack",
                    mode: .region,
                    forceGif: true
                )

                RecordingMenuButton(
                    title: "Voice Only",
                    icon: "mic.fill",
                    mode: .voiceOnly
                )
            }
            .padding(.vertical, 8)

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
        Task { @MainActor in
            // Show window picker first
            let selector = CaptureWindowSelector()
            if let scWindow = await selector.selectWindow() {
                do {
                    let image = try await captureService.captureWindow(scWindow)
                    appState.currentImage = image
                    appState.annotations = []
                    openWindow(id: "editor", value: UUID())
                } catch {
                    print("Capture failed: \(error)")
                }
            } else {
                print("Window selection cancelled")
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

// MARK: - Recording Menu Button (direct recording)
struct RecordingMenuButton: View {
    let title: String
    let icon: String
    let mode: RecordingConfiguration.CaptureMode
    var forceGif: Bool = false
    var withWebcam: Bool = false

    @StateObject private var recordingService = ScreenRecordingService.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: startRecording) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(mode == .voiceOnly ? .blue : .red)

                Text(title)
                    .foregroundColor(.primary)

                Spacer()

                if recordingService.state.isRecording && recordingService.configuration.captureMode == mode {
                    Text(formatTime(recordingService.elapsedTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
        .disabled(recordingService.state.isRecording && recordingService.configuration.captureMode != mode)
    }

    private func startRecording() {
        // If already recording this mode, stop it
        if recordingService.state.isRecording {
            Task {
                do {
                    let url = try await recordingService.stopRecording()
                    // Save to library and show
                    await MainActor.run {
                        showRecordingResult(url: url)
                    }
                } catch {
                    print("❌ Failed to stop recording: \(error)")
                }
            }
            return
        }

        // Set mode and start
        recordingService.configuration.captureMode = mode
        
        // Set output format - GIF only for GIF button, otherwise MP4
        if forceGif {
            recordingService.configuration.outputFormat = .gif
        } else {
            recordingService.configuration.outputFormat = .mp4
        }
        
        // Enable webcam if this is the webcam button
        if withWebcam {
            recordingService.configuration.enableWebcam = true
            // Check camera permission
            Task {
                let hasPermission = await CameraPermission.checkAndRequest()
                if !hasPermission {
                    print("❌ Camera permission denied")
                    return
                }
            }
        }

        switch mode {
        case .region:
            // Need to select region first
            Task { @MainActor in
                print("🎬 MenuBar: Starting region selection...")
                let selector = RecordingRegionSelector()
                if let region = await selector.selectRegion() {
                    print("🎬 MenuBar: Region selected: \(region)")
                    recordingService.configuration.region = region
                    do {
                        try await recordingService.startRecording()
                        print("🎬 MenuBar: Recording started!")
                    } catch {
                        print("❌ MenuBar: Failed to start recording: \(error)")
                    }
                } else {
                    print("⚠️ MenuBar: Region selection cancelled")
                    // Reset recording service state
                    recordingService.resetToIdle()
                }
            }

        case .window:
            // Show window picker to let user select which window to record
            Task { @MainActor in
                print("🎬 MenuBar: Starting window selection...")
                let selector = RecordingWindowSelector()
                if let result = await selector.selectWindow() {
                    print("🎬 MenuBar: Window selected: \(result.title)")
                    recordingService.configuration.windowID = result.windowID
                    do {
                        try await recordingService.startRecording()
                        print("🎬 MenuBar: Recording started for window: \(result.title)")
                    } catch {
                        print("❌ MenuBar: Failed to start recording: \(error)")
                    }
                } else {
                    print("⚠️ MenuBar: Window selection cancelled")
                    recordingService.resetToIdle()
                }
            }

        case .fullScreen, .voiceOnly:
            Task {
                print("🎬 MenuBar: Starting \(mode.rawValue) recording...")
                do {
                    try await recordingService.startRecording()
                    print("🎬 MenuBar: Recording started!")
                } catch {
                    print("❌ MenuBar: Failed to start recording: \(error)")
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func showRecordingResult(url: URL) {
        do {
            // Determine the type from file extension
            let ext = url.pathExtension.lowercased()
            let itemType: LibraryItem.ItemType
            switch ext {
            case "gif":
                itemType = .gif
            case "m4a":
                itemType = .voiceRecording
            default:
                itemType = .recording
            }
            
            // Save to library
            let fileName = url.lastPathComponent
            let name = fileName.replacingOccurrences(of: ".\(ext)", with: "")
            let item = try LibraryService.shared.saveRecording(from: url, type: itemType, name: name, collection: "Recordings")
            
            // Show notification that it was saved
            let notification = NSUserNotification()
            notification.title = "Recording Saved"
            notification.informativeText = "'\(name)' was saved to your library"
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
            
            // Open the file in default app (QuickTime for videos, Preview for GIFs)
            NSWorkspace.shared.open(url)
            
            print("✅ Recording saved to library: \(item.name)")
        } catch {
            print("❌ Failed to save recording to library: \(error)")
            // Still try to open the file
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Record Menu Button (legacy popover - keeping for reference)
struct RecordMenuButton: View {
    @StateObject private var recordingService = ScreenRecordingService.shared
    @State private var showRecordingPanel = false
    @State private var isHovered = false

    var body: some View {
        Button(action: { showRecordingPanel.toggle() }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(recordingService.state.isRecording ? Color.red : Color.primary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)

                    if recordingService.state.isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 20)

                if recordingService.state.isRecording || recordingService.state.isPaused {
                    Text(formatTime(recordingService.elapsedTime))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                } else {
                    Text("Record")
                        .foregroundColor(.primary)
                }

                Spacer()
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
        .popover(isPresented: $showRecordingPanel) {
            RecordingControlsView()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}

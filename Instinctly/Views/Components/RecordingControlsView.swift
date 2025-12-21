import SwiftUI
import AVFoundation
import ScreenCaptureKit

// MARK: - Recording Controls View (Floating Panel)
struct RecordingControlsView: View {
    @StateObject private var recordingService = ScreenRecordingService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var lastRecordingURL: URL?
    @State private var showClipEditor = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: recordingService.configuration.captureMode == .voiceOnly ? "mic.fill" : "record.circle")
                    .foregroundColor(recordingService.configuration.captureMode == .voiceOnly ? .blue : .red)
                Text(recordingService.configuration.captureMode == .voiceOnly ? "Voice Recording" : "Screen Recording")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Show completion view if we have a recording
            if let recordingURL = lastRecordingURL, recordingService.state == .idle {
                RecordingCompleteView(
                    fileURL: recordingURL,
                    onEdit: {
                        showClipEditor = true
                    },
                    onShare: {
                        showShareSheet = true
                    },
                    onNewRecording: {
                        lastRecordingURL = nil
                    },
                    onDismiss: {
                        lastRecordingURL = nil
                        dismiss()
                    }
                )
            } else {
                // Recording state indicator
                RecordingStateView(state: recordingService.state, elapsedTime: recordingService.elapsedTime)

                // Controls based on state
                switch recordingService.state {
                case .idle:
                    RecordingSetupView(configuration: $recordingService.configuration) {
                        Task {
                            try? await recordingService.startRecording()
                        }
                    }

                case .preparing:
                    ProgressView("Preparing...")

                case .recording, .paused:
                    RecordingActiveView(
                        state: recordingService.state,
                        onPause: { recordingService.pauseRecording() },
                        onResume: { recordingService.resumeRecording() },
                        onStop: {
                            Task {
                                if let url = try? await recordingService.stopRecording() {
                                    lastRecordingURL = url
                                }
                            }
                        },
                        onCancel: {
                            Task {
                                await recordingService.cancelRecording()
                            }
                        }
                    )

                case .stopping:
                    ProgressView("Saving...")

                case .error(let message):
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(message)
                            .foregroundColor(.secondary)
                        Button("Try Again") {
                            Task { @MainActor in
                                recordingService.state = .idle
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .sheet(isPresented: $showClipEditor) {
            if let url = lastRecordingURL {
                ClipEditorView(
                    fileURL: url,
                    onSave: { trimmedURL in
                        lastRecordingURL = trimmedURL
                        showClipEditor = false
                    },
                    onCancel: {
                        showClipEditor = false
                    }
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = lastRecordingURL {
                RecordingShareSheet(fileURL: url)
            }
        }
    }
}

// MARK: - Recording Complete View
struct RecordingCompleteView: View {
    let fileURL: URL
    let onEdit: () -> Void
    let onShare: () -> Void
    let onNewRecording: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Recording Saved!")
                .font(.headline)

            // File info
            VStack(spacing: 4) {
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int64 {
                    Text(formatFileSize(size))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    VStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.title2)
                        Text("Trim")
                            .font(.caption)
                    }
                    .frame(width: 70, height: 60)
                }
                .buttonStyle(.bordered)

                Button(action: onShare) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Share")
                            .font(.caption)
                    }
                    .frame(width: 70, height: 60)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.title2)
                        Text("Reveal")
                            .font(.caption)
                    }
                    .frame(width: 70, height: 60)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack {
                Button("New Recording") {
                    onNewRecording()
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Recording Share Sheet
struct RecordingShareSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Share Recording")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            // File preview
            VStack(spacing: 8) {
                Image(systemName: fileIcon)
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Share options
            VStack(spacing: 12) {
                ShareButton(icon: "doc.on.clipboard", title: "Copy to Clipboard", color: .blue) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([fileURL as NSURL])
                }

                ShareButton(icon: "square.and.arrow.up", title: "System Share...", color: .orange) {
                    let picker = NSSharingServicePicker(items: [fileURL])
                    if let view = NSApp.keyWindow?.contentView {
                        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
                    }
                }

                ShareButton(icon: "folder", title: "Show in Finder", color: .gray) {
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
                }
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    private var fileIcon: String {
        switch fileURL.pathExtension.lowercased() {
        case "gif": return "photo.on.rectangle"
        case "mp4", "mov", "webm": return "video.fill"
        case "m4a": return "waveform"
        default: return "doc.fill"
        }
    }
}

// MARK: - Share Button
struct ShareButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recording State View
struct RecordingStateView: View {
    let state: RecordingState
    let elapsedTime: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator
            Circle()
                .fill(indicatorColor)
                .frame(width: 12, height: 12)
                .opacity(state.isRecording ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: state.isRecording)

            // Status text
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            // Timer
            if state.isRecording || state.isPaused {
                Text(formatTime(elapsedTime))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(state.isRecording ? .red : .secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var indicatorColor: Color {
        switch state {
        case .recording: return .red
        case .paused: return .orange
        default: return .gray
        }
    }

    private var statusText: String {
        switch state {
        case .idle: return "Ready to record"
        case .preparing: return "Preparing..."
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .stopping: return "Saving..."
        case .error: return "Error"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Recording Setup View
struct RecordingSetupView: View {
    @Binding var configuration: RecordingConfiguration
    let onStart: () -> Void

    @State private var showWindowPicker = false
    @State private var showRegionSelector = false
    @State private var selectedWindowInfo: String?

    private var isVoiceOnly: Bool {
        configuration.captureMode == .voiceOnly
    }

    private var availableFormats: [RecordingConfiguration.OutputFormat] {
        if isVoiceOnly {
            return [.m4a]
        } else {
            return [.gif, .mp4, .webm, .mov]
        }
    }

    private var needsSelection: Bool {
        switch configuration.captureMode {
        case .window: return configuration.windowID == nil
        case .region: return configuration.region == nil
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Capture Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Capture Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Mode", selection: $configuration.captureMode) {
                    ForEach(RecordingConfiguration.CaptureMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: configuration.captureMode) { _, newValue in
                    // Auto-select appropriate format when switching modes
                    if newValue == .voiceOnly {
                        configuration.outputFormat = .m4a
                    } else if configuration.outputFormat == .m4a {
                        configuration.outputFormat = .mp4
                    }
                    // Clear previous selection when mode changes
                    configuration.windowID = nil
                    configuration.region = nil
                    selectedWindowInfo = nil
                }
            }

            // Selection status for window/region modes
            if configuration.captureMode == .window {
                SelectionStatusView(
                    icon: "macwindow",
                    title: selectedWindowInfo ?? "No window selected",
                    isSelected: configuration.windowID != nil,
                    onSelect: { showWindowPicker = true }
                )
            } else if configuration.captureMode == .region {
                SelectionStatusView(
                    icon: "rectangle.dashed",
                    title: configuration.region != nil ? "Region: \(Int(configuration.region!.width))x\(Int(configuration.region!.height))" : "No region selected",
                    isSelected: configuration.region != nil,
                    onSelect: { showRegionSelector = true }
                )
            }

            // Output Format (hide for voice-only since it's always M4A)
            if !isVoiceOnly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Format")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Format", selection: $configuration.outputFormat) {
                        ForEach(availableFormats, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                // Voice-only indicator
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.blue)
                    Text("Audio will be saved as M4A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }

            // Quality (show for all modes)
            VStack(alignment: .leading, spacing: 8) {
                Text("Quality")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Quality", selection: $configuration.quality) {
                    ForEach(RecordingConfiguration.RecordingQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Audio options (only for video formats, not voice-only)
            if !isVoiceOnly && configuration.outputFormat.supportsAudio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("System Audio", isOn: $configuration.captureAudio)
                    Toggle("Microphone", isOn: $configuration.captureMicrophone)
                }
            }

            // Beta: Webcam (only for video modes)
            if !isVoiceOnly {
                Divider()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Webcam Overlay", isOn: $configuration.enableWebcam)

                        if configuration.enableWebcam {
                            Picker("Position", selection: $configuration.webcamPosition) {
                                ForEach(RecordingConfiguration.WebcamPosition.allCases, id: \.self) { pos in
                                    Text(pos.rawValue).tag(pos)
                                }
                            }

                            Picker("Size", selection: $configuration.webcamSize) {
                                ForEach(RecordingConfiguration.WebcamSize.allCases, id: \.self) { size in
                                    Text(size.rawValue).tag(size)
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Webcam (Beta)")
                        Spacer()
                        Text("BETA")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }

            Divider()

            // Start button
            Button(action: handleStartButton) {
                HStack {
                    Image(systemName: startButtonIcon)
                    Text(startButtonText)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(startButtonTint)
            .controlSize(.large)
            .disabled(needsSelection && !canSelectNow)
        }
        .sheet(isPresented: $showWindowPicker) {
            RecordingWindowPickerView { windowID, windowTitle in
                configuration.windowID = windowID
                selectedWindowInfo = windowTitle
                showWindowPicker = false
            }
        }
        .onChange(of: showRegionSelector) { _, show in
            if show {
                // Show region selector overlay
                selectRegionForRecording()
            }
        }
    }

    private var canSelectNow: Bool {
        configuration.captureMode == .window || configuration.captureMode == .region
    }

    private func handleStartButton() {
        switch configuration.captureMode {
        case .window:
            if configuration.windowID == nil {
                showWindowPicker = true
            } else {
                onStart()
            }
        case .region:
            if configuration.region == nil {
                selectRegionForRecording()
            } else {
                onStart()
            }
        default:
            onStart()
        }
    }

    private func selectRegionForRecording() {
        // Use the existing RegionSelectionOverlay but for recording
        Task { @MainActor in
            let selector = RecordingRegionSelector()
            if let region = await selector.selectRegion() {
                configuration.region = region
            }
        }
    }

    private var startButtonIcon: String {
        if needsSelection {
            return configuration.captureMode == .window ? "macwindow" : "rectangle.dashed"
        }
        return isVoiceOnly ? "mic.fill" : "record.circle"
    }

    private var startButtonTint: Color {
        if needsSelection {
            return .accentColor
        }
        return isVoiceOnly ? .blue : .red
    }

    private var startButtonText: String {
        switch configuration.captureMode {
        case .region:
            return configuration.region == nil ? "Select Region" : "Start Recording"
        case .window:
            return configuration.windowID == nil ? "Select Window" : "Start Recording"
        case .fullScreen:
            return "Start Recording"
        case .voiceOnly:
            return "Start Voice Recording"
        }
    }
}

// MARK: - Selection Status View
struct SelectionStatusView: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .green : .secondary)
                Text(title)
                    .font(.caption)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("Select")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .background(isSelected ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recording Window Picker
struct RecordingWindowPickerView: View {
    let onSelect: (CGWindowID, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [(id: CGWindowID, title: String, appName: String, icon: NSImage?)] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Select Window to Record")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }

            if isLoading {
                ProgressView("Loading windows...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No windows found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(windows, id: \.id) { window in
                            WindowRowView(
                                title: window.title,
                                appName: window.appName,
                                icon: window.icon
                            ) {
                                onSelect(window.id, "\(window.appName): \(window.title)")
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 400)
        .onAppear {
            loadWindows()
        }
    }

    private func loadWindows() {
        Task {
            do {
                let content = try await SCShareableContent.current
                let windowList = content.windows.compactMap { window -> (id: CGWindowID, title: String, appName: String, icon: NSImage?)? in
                    guard let title = window.title, !title.isEmpty,
                          let app = window.owningApplication,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                        return nil
                    }
                    let appName = app.applicationName
                    let icon = NSRunningApplication(processIdentifier: app.processID)?.icon
                    return (window.windowID, title, appName, icon)
                }

                await MainActor.run {
                    windows = windowList
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Window Row View
struct WindowRowView: View {
    let title: String
    let appName: String
    let icon: NSImage?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "macwindow")
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(appName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recording Region Selector
@MainActor
class RecordingRegionSelector {
    func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            let window = RegionSelectionWindowForRecording { rect in
                continuation.resume(returning: rect)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Region Selection Window for Recording
class RegionSelectionWindowForRecording: NSWindow {
    private var selectionView: RegionSelectionViewForRecording!
    private var onComplete: ((CGRect?) -> Void)?

    init(onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete

        guard let screen = NSScreen.main else {
            onComplete(nil)
            super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            return
        }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false

        selectionView = RegionSelectionViewForRecording(frame: screen.frame) { [weak self] rect in
            self?.close()
            self?.onComplete?(rect)
        }
        self.contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Region Selection View for Recording
class RegionSelectionViewForRecording: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var onComplete: ((CGRect?) -> Void)?

    init(frame: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // Selection rectangle
        if let start = startPoint, let current = currentPoint {
            let rect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )

            // Clear the selection area
            NSColor.clear.setFill()
            rect.fill()

            // Draw border
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()

            // Draw size label
            let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let textSize = sizeText.size(withAttributes: attrs)
            let textRect = NSRect(
                x: rect.midX - textSize.width / 2,
                y: rect.maxY + 8,
                width: textSize.width + 8,
                height: textSize.height + 4
            )
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
            sizeText.draw(at: NSPoint(x: textRect.minX + 4, y: textRect.minY + 2), withAttributes: attrs)
        }

        // Instructions
        let instructions = "Drag to select recording region • Press Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ]
        let textSize = instructions.size(withAttributes: attrs)
        instructions.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: bounds.maxY - 50), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let current = currentPoint else {
            onComplete?(nil)
            return
        }

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        if rect.width > 10 && rect.height > 10 {
            // Convert to screen coordinates (flip Y)
            if let screen = NSScreen.main {
                let screenRect = CGRect(
                    x: rect.origin.x,
                    y: screen.frame.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                onComplete?(screenRect)
            } else {
                onComplete?(rect)
            }
        } else {
            onComplete?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onComplete?(nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Recording Active View
struct RecordingActiveView: View {
    let state: RecordingState
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Main controls
            HStack(spacing: 20) {
                // Pause/Resume
                Button(action: state.isPaused ? onResume : onPause) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .frame(width: 50, height: 50)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(25)

                // Stop (save)
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 60, height: 60)
                .background(Color.red)
                .cornerRadius(30)

                // Cancel
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .frame(width: 50, height: 50)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(25)
            }

            // Labels
            HStack(spacing: 40) {
                Text(state.isPaused ? "Resume" : "Pause")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Stop")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Cancel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Menu Bar Recording Button
struct MenuBarRecordingButton: View {
    @StateObject private var recordingService = ScreenRecordingService.shared
    @State private var showRecordingPanel = false

    var body: some View {
        Button(action: { showRecordingPanel.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: recordingService.state.isRecording ? "record.circle.fill" : "record.circle")
                    .foregroundColor(recordingService.state.isRecording ? .red : .primary)

                if recordingService.state.isRecording || recordingService.state.isPaused {
                    Text(formatTime(recordingService.elapsedTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                } else {
                    Text("Record")
                }
            }
        }
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

// MARK: - Quick Record Button (for toolbar)
struct QuickRecordButton: View {
    @StateObject private var recordingService = ScreenRecordingService.shared
    @State private var showControls = false

    var body: some View {
        Button(action: handleClick) {
            ZStack {
                Circle()
                    .fill(recordingService.state.isRecording ? Color.red : Color.clear)
                    .frame(width: 32, height: 32)

                Image(systemName: recordingService.state.isRecording ? "stop.fill" : "record.circle")
                    .foregroundColor(recordingService.state.isRecording ? .white : .red)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showControls) {
            RecordingControlsView()
        }
        .help(recordingService.state.isRecording ? "Stop Recording" : "Start Recording")
    }

    private func handleClick() {
        if recordingService.state.isRecording {
            Task {
                _ = try? await recordingService.stopRecording()
            }
        } else {
            showControls = true
        }
    }
}

#Preview {
    RecordingControlsView()
}

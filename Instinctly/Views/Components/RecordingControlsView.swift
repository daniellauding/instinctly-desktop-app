import SwiftUI
import AVFoundation

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

    @State private var showRegionPicker = false

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
                }
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
            Button(action: onStart) {
                HStack {
                    Image(systemName: isVoiceOnly ? "mic.fill" : "record.circle")
                    Text(startButtonText)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isVoiceOnly ? .blue : .red)
            .controlSize(.large)
        }
    }

    private var startButtonText: String {
        switch configuration.captureMode {
        case .region: return "Select Region & Record"
        case .window: return "Select Window & Record"
        case .fullScreen: return "Start Recording"
        case .voiceOnly: return "Start Voice Recording"
        }
    }
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

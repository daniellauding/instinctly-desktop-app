import SwiftUI
import AVFoundation

// MARK: - Recording Controls View (Floating Panel)
struct RecordingControlsView: View {
    @StateObject private var recordingService = ScreenRecordingService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "record.circle")
                    .foregroundColor(.red)
                Text("Screen Recording")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

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
                            _ = try? await recordingService.stopRecording()
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
        .padding(20)
        .frame(width: 320)
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
            }

            // Output Format
            VStack(alignment: .leading, spacing: 8) {
                Text("Output Format")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Format", selection: $configuration.outputFormat) {
                    ForEach(RecordingConfiguration.OutputFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Quality
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

            // Audio options (only for video formats)
            if configuration.outputFormat.supportsAudio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("System Audio", isOn: $configuration.captureAudio)
                    Toggle("Microphone", isOn: $configuration.captureMicrophone)
                }
            }

            Divider()

            // Beta: Webcam
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

            Divider()

            // Start button
            Button(action: onStart) {
                HStack {
                    Image(systemName: "record.circle")
                    Text(startButtonText)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    private var startButtonText: String {
        switch configuration.captureMode {
        case .region: return "Select Region & Record"
        case .window: return "Select Window & Record"
        case .fullScreen: return "Start Recording"
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

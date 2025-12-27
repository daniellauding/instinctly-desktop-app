import SwiftUI
import AVFoundation
import AVKit
import os.log

private let clipLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "ClipEditor")

// MARK: - Clip Editor View
struct ClipEditorView: View {
    let fileURL: URL
    let onSave: (URL) -> Void
    let onCancel: () -> Void

    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var isPlaying = false
    @State private var isTrimming = false
    @State private var trimProgress: Double = 0
    @State private var errorMessage: String?
    @State private var includeAudio = true

    private let timeObserverInterval = CMTime(seconds: 0.1, preferredTimescale: 600)

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Trim Recording")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)
            }

            // Video/Audio Preview
            if isVideoFile {
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 200)
                        .cornerRadius(8)
                    
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(height: 200)
                            .cornerRadius(8)
                            .onAppear {
                                // Small delay to avoid layout conflicts
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if duration > 0 {
                                        player.play()
                                    }
                                }
                            }
                    } else {
                        VStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundColor(.white)
                        }
                    }
                }
            } else {
                // Audio waveform placeholder
                AudioWaveformView(duration: duration, currentTime: currentTime, startTime: startTime, endTime: endTime)
                    .frame(height: 100)
            }

            // Time Display
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text("Duration: \(formatTime(endTime - startTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(duration))
                    .font(.system(.caption, design: .monospaced))
            }

            // Timeline Trimmer
            TrimSlider(
                duration: duration,
                currentTime: $currentTime,
                startTime: $startTime,
                endTime: $endTime,
                onSeek: { time in
                    seek(to: time)
                }
            )
            .frame(height: 60)

            // Playback Controls
            HStack(spacing: 20) {
                Button(action: skipBackward) {
                    Image(systemName: "gobackward.5")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button(action: skipForward) {
                    Image(systemName: "goforward.5")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            // Trim Presets
            HStack(spacing: 12) {
                TrimPresetButton(title: "First 10s") {
                    startTime = 0
                    endTime = min(10, duration)
                }

                TrimPresetButton(title: "Last 10s") {
                    startTime = max(0, duration - 10)
                    endTime = duration
                }

                TrimPresetButton(title: "Reset") {
                    startTime = 0
                    endTime = duration
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Audio Options
            if hasAudio {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Options")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Toggle("Include Audio", isOn: $includeAudio)
                        .toggleStyle(.checkbox)
                }
            }

            Divider()

            // Action Buttons
            HStack {
                Button("Discard Changes") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                if isTrimming {
                    ProgressView(value: trimProgress)
                        .frame(width: 100)
                    Text("Trimming...")
                        .font(.caption)
                } else {
                    Button("Save Trimmed Clip") {
                        trimAndSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(startTime == 0 && endTime == duration)
                }
            }
        }
        .padding(20)
        .frame(width: 500, height: isVideoFile ? 500 : 400)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    // MARK: - Helpers

    private var isVideoFile: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ["mp4", "mov", "webm", "gif"].contains(ext)
    }
    
    private var hasAudio: Bool {
        let ext = fileURL.pathExtension.lowercased()
        return ["mp4", "mov", "webm", "m4a"].contains(ext)
    }

    private func setupPlayer() {
        // Ensure file exists before creating asset
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            clipLogger.error("File does not exist at path: \(fileURL.path)")
            return
        }
        
        let asset = AVAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)

        // Get duration with retry logic
        Task {
            var retryCount = 0
            let maxRetries = 3
            
            while retryCount < maxRetries {
                do {
                    // Wait a moment for file to be fully written if it's a temp file
                    if retryCount > 0 {
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    }
                    
                    let durationValue = try await asset.load(.duration)
                    let durationSeconds = CMTimeGetSeconds(durationValue)
                    
                    guard durationSeconds.isFinite && durationSeconds > 0 else {
                        throw NSError(domain: "ClipEditor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid duration: \(durationSeconds)"])
                    }
                    
                    await MainActor.run {
                        self.duration = durationSeconds
                        self.endTime = durationSeconds
                        clipLogger.info("Loaded clip: \(durationSeconds)s")
                    }
                    return // Success, exit retry loop
                    
                } catch {
                    retryCount += 1
                    clipLogger.warning("Attempt \(retryCount) failed to load duration: \(error.localizedDescription)")
                    
                    if retryCount >= maxRetries {
                        await MainActor.run {
                            clipLogger.error("Failed to load duration after \(maxRetries) attempts: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }

        // Add time observer
        player?.addPeriodicTimeObserver(forInterval: timeObserverInterval, queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                currentTime = seconds

                // Loop within trim range
                if seconds >= endTime {
                    seek(to: startTime)
                    if isPlaying {
                        player?.play()
                    }
                }
            }
        }
    }

    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            // Start from trim start if before it
            if currentTime < startTime || currentTime >= endTime {
                seek(to: startTime)
            }
            player?.play()
        }
        isPlaying.toggle()
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    private func skipBackward() {
        seek(to: max(startTime, currentTime - 5))
    }

    private func skipForward() {
        seek(to: min(endTime, currentTime + 5))
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }

    private func trimAndSave() {
        isTrimming = true
        errorMessage = nil

        Task {
            do {
                let trimmedURL = try await trimMedia(
                    inputURL: fileURL,
                    startTime: startTime,
                    endTime: endTime,
                    includeAudio: includeAudio
                ) { progress in
                    Task { @MainActor in
                        trimProgress = progress
                    }
                }

                await MainActor.run {
                    isTrimming = false
                    onSave(trimmedURL)
                }
            } catch {
                await MainActor.run {
                    isTrimming = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func trimMedia(inputURL: URL, startTime: Double, endTime: Double, includeAudio: Bool, progress: @escaping (Double) -> Void) async throws -> URL {
        let sourceAsset = AVAsset(url: inputURL)
        
        // Create mutable composition to control tracks
        let composition = AVMutableComposition()
        
        // Add video track if it exists
        if let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first {
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
            let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
            
            try videoTrack?.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        }
        
        // Add audio track only if includeAudio is true and audio track exists
        if includeAudio, let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first {
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
            let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
            
            try audioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
        }

        // Create export session with the composition
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipEditorError.exportSessionCreationFailed
        }

        // Output URL
        let outputDir = FileManager.default.temporaryDirectory
        let outputName = "trimmed_\(inputURL.deletingPathExtension().lastPathComponent).\(inputURL.pathExtension)"
        let outputURL = outputDir.appendingPathComponent(outputName)

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType(for: inputURL.pathExtension)
        
        // Note: Time range is already handled in the composition

        // Monitor progress
        let progressTask = Task {
            while exportSession.status == .exporting {
                progress(Double(exportSession.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // Export
        await exportSession.export()
        progressTask.cancel()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? ClipEditorError.exportFailed
        }

        // Move to Downloads
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let finalURL = downloadsURL.appendingPathComponent(outputName)

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: outputURL, to: finalURL)

        clipLogger.info("Trimmed clip saved to: \(finalURL.path)")
        
        // Notify that a trimmed clip was saved
        NotificationCenter.default.post(name: .recordingSaved, object: finalURL)

        // Reveal in Finder
        NSWorkspace.shared.selectFile(finalURL.path, inFileViewerRootedAtPath: "")

        return finalURL
    }

    private func outputFileType(for ext: String) -> AVFileType {
        switch ext.lowercased() {
        case "mp4": return .mp4
        case "mov": return .mov
        case "m4a": return .m4a
        default: return .mp4
        }
    }
}

// MARK: - Trim Slider
struct TrimSlider: View {
    let duration: Double
    @Binding var currentTime: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    let onSeek: (Double) -> Void

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingPlayhead = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 40)

                // Trim range highlight
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: rangeWidth(in: width), height: 40)
                    .offset(x: startPosition(in: width))

                // Start handle
                TrimHandle(position: startPosition(in: width), isLeft: true)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingStart = true
                                let newStart = max(0, min(endTime - 1, positionToTime(value.location.x, in: width)))
                                startTime = newStart
                            }
                            .onEnded { _ in
                                isDraggingStart = false
                                onSeek(startTime)
                            }
                    )

                // End handle
                TrimHandle(position: endPosition(in: width), isLeft: false)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingEnd = true
                                let newEnd = min(duration, max(startTime + 1, positionToTime(value.location.x, in: width)))
                                endTime = newEnd
                            }
                            .onEnded { _ in
                                isDraggingEnd = false
                                onSeek(endTime - 0.1)
                            }
                    )

                // Playhead
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: height)
                    .offset(x: playheadPosition(in: width))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingPlayhead = true
                                let newTime = positionToTime(value.location.x, in: width)
                                currentTime = max(startTime, min(endTime, newTime))
                            }
                            .onEnded { _ in
                                isDraggingPlayhead = false
                                onSeek(currentTime)
                            }
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let time = positionToTime(location.x, in: width)
                currentTime = max(startTime, min(endTime, time))
                onSeek(currentTime)
            }
        }
    }

    private func startPosition(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return (startTime / duration) * width
    }

    private func endPosition(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return width }
        return (endTime / duration) * width
    }

    private func rangeWidth(in width: CGFloat) -> CGFloat {
        endPosition(in: width) - startPosition(in: width)
    }

    private func playheadPosition(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return (currentTime / duration) * width
    }

    private func positionToTime(_ x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return (Double(x) / Double(width)) * duration
    }
}

// MARK: - Trim Handle
struct TrimHandle: View {
    let position: CGFloat
    let isLeft: Bool

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 12, height: 50)
                .overlay(
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Color.white.opacity(0.8))
                                .frame(width: 4, height: 2)
                        }
                    }
                )
        }
        .offset(x: position - (isLeft ? 0 : 12))
        .zIndex(1)
    }
}

// MARK: - Trim Preset Button
struct TrimPresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Audio Waveform View (Placeholder)
struct AudioWaveformView: View {
    let duration: Double
    let currentTime: Double
    let startTime: Double
    let endTime: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))

                // Waveform visualization (simplified)
                HStack(spacing: 2) {
                    ForEach(0..<50, id: \.self) { i in
                        let height = CGFloat.random(in: 0.2...1.0)
                        let inRange = isInTrimRange(index: i, total: 50)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(inRange ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 3, height: geometry.size.height * height * 0.8)
                    }
                }
                .padding(.horizontal, 8)

                // Playhead indicator
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: playheadOffset(in: geometry.size.width))

                // Mic icon
                Image(systemName: "waveform")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary.opacity(0.3))
            }
        }
    }

    private func isInTrimRange(index: Int, total: Int) -> Bool {
        guard duration > 0 else { return true }
        let position = Double(index) / Double(total) * duration
        return position >= startTime && position <= endTime
    }

    private func playheadOffset(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return ((currentTime / duration) - 0.5) * width
    }
}

// MARK: - Errors
enum ClipEditorError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed:
            return "Failed to export trimmed clip"
        }
    }
}

#Preview {
    ClipEditorView(
        fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
        onSave: { _ in },
        onCancel: { }
    )
}

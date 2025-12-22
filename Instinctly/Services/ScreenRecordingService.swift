import Foundation
import AppKit
import AVFoundation
import ScreenCaptureKit
import Combine
import os.log
import UniformTypeIdentifiers

private let recordLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "ScreenRecording")

// MARK: - Recording Configuration
struct RecordingConfiguration {
    var captureMode: CaptureMode = .region
    var outputFormat: OutputFormat = .mp4
    var frameRate: Int = 30
    var quality: RecordingQuality = .high
    var captureAudio: Bool = true
    var captureMicrophone: Bool = false
    var region: CGRect?
    var windowID: CGWindowID?

    // Beta: Webcam overlay
    var enableWebcam: Bool = false
    var webcamPosition: WebcamPosition = .bottomRight
    var webcamSize: WebcamSize = .medium

    enum WebcamPosition: String, CaseIterable {
        case topLeft = "Top Left"
        case topRight = "Top Right"
        case bottomLeft = "Bottom Left"
        case bottomRight = "Bottom Right"

        var alignment: (x: CGFloat, y: CGFloat) {
            switch self {
            case .topLeft: return (0.05, 0.95)
            case .topRight: return (0.95, 0.95)
            case .bottomLeft: return (0.05, 0.05)
            case .bottomRight: return (0.95, 0.05)
            }
        }
    }

    enum WebcamSize: String, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"

        var percentage: CGFloat {
            switch self {
            case .small: return 0.15
            case .medium: return 0.25
            case .large: return 0.35
            }
        }
    }

    enum CaptureMode: String, CaseIterable {
        case region = "Region"
        case window = "Window"
        case fullScreen = "Full Screen"
        case voiceOnly = "Voice Only"

        var icon: String {
            switch self {
            case .region: return "rectangle.dashed"
            case .window: return "macwindow"
            case .fullScreen: return "rectangle.on.rectangle"
            case .voiceOnly: return "mic.fill"
            }
        }

        var isVideoMode: Bool {
            self != .voiceOnly
        }
    }

    enum OutputFormat: String, CaseIterable {
        case gif = "GIF"
        case mp4 = "MP4"
        case webm = "WebM"
        case mov = "MOV"
        case m4a = "M4A"  // Audio only

        var fileExtension: String { rawValue.lowercased() }

        var supportsAudio: Bool {
            switch self {
            case .gif: return false
            case .mp4, .webm, .mov, .m4a: return true
            }
        }

        var isAudioOnly: Bool {
            self == .m4a
        }

        var isVideoFormat: Bool {
            switch self {
            case .gif, .mp4, .webm, .mov: return true
            case .m4a: return false
            }
        }
    }

    enum RecordingQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var videoBitrate: Int {
            switch self {
            case .low: return 1_000_000
            case .medium: return 3_000_000
            case .high: return 8_000_000
            }
        }

        var gifColors: Int {
            switch self {
            case .low: return 64
            case .medium: return 128
            case .high: return 256
            }
        }
    }
}

// MARK: - Recording State
enum RecordingState: Equatable {
    case idle
    case preparing
    case recording(duration: TimeInterval)
    case paused(duration: TimeInterval)
    case stopping
    case error(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

// MARK: - Screen Recording Service
@MainActor
class ScreenRecordingService: NSObject, ObservableObject {
    static let shared = ScreenRecordingService()

    @Published var state: RecordingState = .idle
    @Published var configuration = RecordingConfiguration()
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentFileURL: URL?

    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var lastPauseTime: Date?
    private var timer: Timer?

    private var gifFrames: [(CGImage, TimeInterval)] = []
    private var lastFrameTime: TimeInterval = 0

    private var recordingOverlay: RecordingOverlayWindowController?

    // Voice-only recording
    private var audioRecorder: AVAudioRecorder?

    override init() {
        super.init()
        recordLogger.info("🎬 ScreenRecordingService initialized")
    }

    // MARK: - Public API

    /// Start recording with current configuration
    func startRecording() async throws {
        guard state == .idle else {
            recordLogger.warning("⚠️ Cannot start: already recording")
            return
        }

        // Handle voice-only recording separately
        if configuration.captureMode == .voiceOnly {
            try await startVoiceOnlyRecording()
            return
        }

        state = .preparing
        recordLogger.info("🎬 Starting recording with mode: \(self.configuration.captureMode.rawValue)")

        do {
            // Get shareable content
            let content = try await SCShareableContent.current

            // Create content filter based on mode
            let filter: SCContentFilter

            switch configuration.captureMode {
            case .fullScreen:
                guard let display = content.displays.first else {
                    throw RecordingError.noDisplayAvailable
                }
                filter = SCContentFilter(display: display, excludingWindows: [])

            case .window:
                guard let windowID = configuration.windowID,
                      let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw RecordingError.noWindowSelected
                }
                filter = SCContentFilter(desktopIndependentWindow: window)

            case .region:
                guard configuration.region != nil else {
                    throw RecordingError.noRegionSelected
                }
                guard let display = content.displays.first else {
                    throw RecordingError.noDisplayAvailable
                }
                // For region, we capture full display and crop later
                filter = SCContentFilter(display: display, excludingWindows: [])

            case .voiceOnly:
                // Handled above
                return
            }

            // Configure stream
            let streamConfig = SCStreamConfiguration()
            streamConfig.width = Int(filter.contentRect.width) * 2
            streamConfig.height = Int(filter.contentRect.height) * 2
            streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
            streamConfig.showsCursor = true
            streamConfig.queueDepth = 5

            // Audio configuration
            if configuration.captureAudio && configuration.outputFormat.supportsAudio {
                streamConfig.capturesAudio = true
                streamConfig.sampleRate = 48000
                streamConfig.channelCount = 2
            }

            // Setup output file
            let fileName = "Instinctly_\(formatDateForFilename()).\(configuration.outputFormat.fileExtension)"
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            currentFileURL = outputURL

            // Setup asset writer for video formats
            if configuration.outputFormat != .gif {
                try setupAssetWriter(url: outputURL, size: CGSize(width: streamConfig.width, height: streamConfig.height))
            } else {
                gifFrames = []
            }

            // Create stream output handler
            streamOutput = RecordingStreamOutput(service: self)

            // Create and start stream
            stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)

            try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))

            if configuration.captureAudio && configuration.outputFormat.supportsAudio {
                try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
            }

            try await stream?.startCapture()

            // Start timer
            recordingStartTime = Date()
            pausedDuration = 0
            startTimer()

            // Show recording overlay for region mode
            if configuration.captureMode == .region, let region = configuration.region {
                showRecordingOverlay(for: region)
            }

            state = .recording(duration: 0)
            recordLogger.info("✅ Recording started")

            // Show floating control panel
            FloatingRecordingPanelController.shared.showPanel()

        } catch {
            state = .error(error.localizedDescription)
            recordLogger.error("❌ Failed to start recording: \(error.localizedDescription)")
            throw error
        }
    }

    /// Pause recording
    func pauseRecording() {
        guard case .recording = state else { return }
        lastPauseTime = Date()
        state = .paused(duration: elapsedTime)
        timer?.invalidate()
        recordLogger.info("⏸️ Recording paused at \(self.elapsedTime)s")
    }

    /// Resume recording
    func resumeRecording() {
        guard case .paused = state else { return }
        if let pauseStart = lastPauseTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }
        startTimer()
        state = .recording(duration: elapsedTime)
        recordLogger.info("▶️ Recording resumed")
    }

    /// Stop recording and save
    func stopRecording() async throws -> URL {
        guard state.isRecording || state.isPaused else {
            throw RecordingError.notRecording
        }

        state = .stopping
        timer?.invalidate()
        recordLogger.info("🛑 Stopping recording...")

        // Hide overlays and panels
        hideRecordingOverlay()
        FloatingRecordingPanelController.shared.hidePanel()

        // Handle voice-only recording
        if configuration.captureMode == .voiceOnly {
            return try await stopVoiceOnlyRecording()
        }

        // Stop capture
        try await stream?.stopCapture()
        stream = nil

        // Finalize output
        guard let outputURL = currentFileURL else {
            throw RecordingError.noOutputFile
        }

        if configuration.outputFormat == .gif {
            // Encode GIF
            try await encodeGif(to: outputURL)
        } else {
            // Finalize video
            await finalizeAssetWriter()
        }

        // Save using NSSavePanel for proper sandbox permissions
        let finalURL = try await saveRecordingWithPanel(tempURL: outputURL)

        state = .idle
        recordLogger.info("✅ Recording saved to: \(finalURL.path)")

        // Also save to library for Collections view
        await saveToLibrary(url: finalURL)

        // Open the recording in the default app (e.g., QuickTime for videos)
        NSWorkspace.shared.open(finalURL)

        return finalURL
    }

    /// Save recording to local library
    private func saveToLibrary(url: URL) async {
        await MainActor.run {
            let itemType: LibraryItem.ItemType
            switch configuration.outputFormat {
            case .gif:
                itemType = .gif
            case .m4a:
                itemType = .voiceRecording
            default:
                itemType = .recording
            }

            do {
                _ = try LibraryService.shared.saveRecording(
                    from: url,
                    type: itemType,
                    collection: "Recordings"
                )
                recordLogger.info("📚 Recording added to library")
            } catch {
                recordLogger.warning("⚠️ Failed to save to library: \(error.localizedDescription)")
            }
        }
    }

    /// Show save panel to let user choose location (sandbox-safe)
    private func saveRecordingWithPanel(tempURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.mpeg4Movie, .gif, .quickTimeMovie, .mpeg4Audio]
                savePanel.nameFieldStringValue = tempURL.lastPathComponent
                savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                savePanel.title = "Save Recording"
                savePanel.message = "Choose where to save your recording"
                savePanel.canCreateDirectories = true

                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        do {
                            // Remove existing file if present
                            if FileManager.default.fileExists(atPath: url.path) {
                                try FileManager.default.removeItem(at: url)
                            }
                            // Copy to user-selected location
                            try FileManager.default.copyItem(at: tempURL, to: url)
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempURL)
                            recordLogger.info("✅ Recording saved to: \(url.path)")
                            continuation.resume(returning: url)
                        } catch {
                            recordLogger.error("❌ Failed to save: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                        }
                    } else {
                        // User cancelled - keep file in temp and return that
                        recordLogger.info("⚠️ Save cancelled, file remains at: \(tempURL.path)")
                        continuation.resume(returning: tempURL)
                    }
                }
            }
        }
    }

    /// Cancel recording without saving
    func cancelRecording() async {
        timer?.invalidate()
        hideRecordingOverlay()
        FloatingRecordingPanelController.shared.hidePanel()

        // Handle voice-only recording
        if configuration.captureMode == .voiceOnly {
            audioRecorder?.stop()
            audioRecorder = nil
            if let url = currentFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            state = .idle
            recordLogger.info("❌ Voice recording cancelled")
            return
        }

        try? await stream?.stopCapture()
        stream = nil

        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }

        assetWriter?.cancelWriting()
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        gifFrames = []

        state = .idle
        recordLogger.info("❌ Recording cancelled")
    }

    // MARK: - Voice-Only Recording

    /// Start voice-only recording using AVAudioRecorder
    private func startVoiceOnlyRecording() async throws {
        state = .preparing
        recordLogger.info("🎤 Starting voice-only recording")

        // Create output file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_\(Date().timeIntervalSince1970).m4a"
        let outputURL = tempDir.appendingPathComponent(fileName)
        currentFileURL = outputURL

        // Configure audio settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: outputURL, settings: settings)
            audioRecorder?.prepareToRecord()

            guard audioRecorder?.record() == true else {
                throw RecordingError.audioRecorderFailed
            }

            // Start timer
            recordingStartTime = Date()
            pausedDuration = 0
            elapsedTime = 0
            startTimer()

            state = .recording(duration: 0)
            recordLogger.info("🎤 Voice recording started")

            // Show floating control panel
            FloatingRecordingPanelController.shared.showPanel()
        } catch {
            state = .error("Failed to start voice recording: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stop voice-only recording and save
    private func stopVoiceOnlyRecording() async throws -> URL {
        audioRecorder?.stop()
        audioRecorder = nil

        guard let outputURL = currentFileURL else {
            throw RecordingError.noOutputFile
        }

        // Save using NSSavePanel for proper sandbox permissions
        let finalURL = try await saveRecordingWithPanel(tempURL: outputURL)

        state = .idle
        recordLogger.info("✅ Voice recording saved to: \(finalURL.path)")

        // Also save to library for Collections view
        await saveToLibrary(url: finalURL)

        // Open the recording in the default app
        NSWorkspace.shared.open(finalURL)

        return finalURL
    }

    // MARK: - Frame Processing

    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard case .recording = state else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if configuration.outputFormat == .gif {
            // Store frame for GIF encoding
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let time = CMTimeGetSeconds(timestamp)

                    // Only capture frames at GIF frame rate (10 fps for smaller files)
                    let gifFrameInterval = 1.0 / 10.0
                    if time - lastFrameTime >= gifFrameInterval {
                        gifFrames.append((cgImage, time))
                        lastFrameTime = time
                    }
                }
            }
        } else {
            // Write to video file
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        }
    }

    func processAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard case .recording = state,
              configuration.captureAudio,
              configuration.outputFormat.supportsAudio else { return }

        if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
    }

    // MARK: - Private Methods

    private func setupAssetWriter(url: URL, size: CGSize) throws {
        let fileType: AVFileType
        switch configuration.outputFormat {
        case .mp4: fileType = .mp4
        case .mov: fileType = .mov
        case .webm: fileType = .mp4 // WebM needs post-processing
        default: return
        }

        assetWriter = try AVAssetWriter(url: url, fileType: fileType)

        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.quality.videoBitrate,
                AVVideoExpectedSourceFrameRateKey: configuration.frameRate
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        if assetWriter?.canAdd(videoInput!) == true {
            assetWriter?.add(videoInput!)
        }

        // Audio settings
        if configuration.captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]

            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true

            if assetWriter?.canAdd(audioInput!) == true {
                assetWriter?.add(audioInput!)
            }
        }

        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
    }

    private func finalizeAssetWriter() async {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        await withCheckedContinuation { continuation in
            assetWriter?.finishWriting {
                continuation.resume()
            }
        }

        assetWriter = nil
        videoInput = nil
        audioInput = nil
    }

    private func encodeGif(to url: URL) async throws {
        recordLogger.info("🎨 Encoding GIF with \(self.gifFrames.count) frames...")

        guard !gifFrames.isEmpty else {
            throw RecordingError.noFramesCaptured
        }

        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            gifFrames.count,
            nil
        )

        guard let destination = destination else {
            throw RecordingError.gifEncodingFailed
        }

        // GIF properties
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0 // Loop forever
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Frame delay
        let frameDelay = 1.0 / 10.0 // 10 fps
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        // Add frames
        for (frame, _) in gifFrames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        if !CGImageDestinationFinalize(destination) {
            throw RecordingError.gifEncodingFailed
        }

        gifFrames = []
        recordLogger.info("✅ GIF encoded successfully")
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let startTime = self.recordingStartTime else { return }

                self.elapsedTime = Date().timeIntervalSince(startTime) - self.pausedDuration
                if case .recording = self.state {
                    self.state = .recording(duration: self.elapsedTime)
                }
            }
        }
    }

    private func showRecordingOverlay(for region: CGRect) {
        recordingOverlay = RecordingOverlayWindowController(region: region)
        recordingOverlay?.showWindow(nil)
    }

    private func hideRecordingOverlay() {
        recordingOverlay?.close()
        recordingOverlay = nil
    }

    private func formatDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Stream Output Handler
class RecordingStreamOutput: NSObject, SCStreamOutput {
    weak var service: ScreenRecordingService?

    init(service: ScreenRecordingService) {
        self.service = service
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let service = service else { return }

        Task { @MainActor in
            switch type {
            case .screen:
                service.processVideoFrame(sampleBuffer)
            case .audio:
                service.processAudioFrame(sampleBuffer)
            case .microphone:
                service.processAudioFrame(sampleBuffer)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Recording Overlay Window
class RecordingOverlayWindowController: NSWindowController {
    init(region: CGRect) {
        let window = NSWindow(
            contentRect: region,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false

        super.init(window: window)

        // Add recording indicator border
        let borderView = RecordingBorderView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(borderView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Recording Border View
class RecordingBorderView: NSView {
    private var pulseAnimation: Timer?
    private var borderOpacity: CGFloat = 1.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        startPulse()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 4
        NSColor.red.withAlphaComponent(borderOpacity).setStroke()
        path.stroke()

        // Recording indicator dot
        let dotSize: CGFloat = 12
        let dotRect = CGRect(x: 10, y: bounds.height - 22, width: dotSize, height: dotSize)
        NSColor.red.withAlphaComponent(borderOpacity).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private func startPulse() {
        pulseAnimation = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.borderOpacity = self?.borderOpacity == 1.0 ? 0.5 : 1.0
            self?.needsDisplay = true
        }
    }

    deinit {
        pulseAnimation?.invalidate()
    }
}

// MARK: - Recording Errors
enum RecordingError: LocalizedError {
    case noDisplayAvailable
    case noWindowSelected
    case noRegionSelected
    case notRecording
    case noOutputFile
    case noFramesCaptured
    case gifEncodingFailed
    case videoEncodingFailed
    case audioRecorderFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available for recording"
        case .noWindowSelected: return "No window selected for recording"
        case .noRegionSelected: return "No region selected for recording"
        case .notRecording: return "Not currently recording"
        case .noOutputFile: return "No output file specified"
        case .noFramesCaptured: return "No frames were captured"
        case .gifEncodingFailed: return "Failed to encode GIF"
        case .videoEncodingFailed: return "Failed to encode video"
        case .audioRecorderFailed: return "Failed to start audio recording"
        }
    }
}

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
    private var firstFrameTime: CMTime?
    private var sessionStarted = false

    private var gifFrames: [(CGImage, TimeInterval)] = []
    private var lastFrameTime: TimeInterval = 0

    private var recordingOverlay: RecordingOverlayWindowController?

    // Voice-only recording
    private var audioRecorder: AVAudioRecorder?

    // Region capture - store for frame cropping
    private var captureRegion: CGRect?
    private var displayScaleFactor: CGFloat = 2.0

    // Preview callback - called when recording stops to show preview
    var onRecordingComplete: ((URL) -> Void)?

    // Webcam capture
    private var webcamManager: WebcamCaptureManager?
    private var webcamPreviewWindow: WebcamPreviewWindowController?

    override init() {
        super.init()
        recordLogger.info("🎬 ScreenRecordingService initialized")
    }

    // MARK: - Public API

    /// Start recording with current configuration
    func startRecording() async throws {
        // Allow starting from idle or error states (auto-reset from error)
        switch state {
        case .idle:
            break // OK to start
        case .error:
            recordLogger.info("🔄 Auto-resetting from error state to start new recording")
            resetToIdle()
        default:
            recordLogger.warning("⚠️ Cannot start: already recording. Current state: \(String(describing: self.state))")
            throw RecordingError.alreadyRecording
        }

        // Handle voice-only recording separately
        if configuration.captureMode == .voiceOnly {
            try await startVoiceOnlyRecording()
            return
        }
        
        // Check screen recording permission first
        if await !ScreenRecordingPermission.hasPermission() {
            ScreenRecordingPermission.requestPermission()
            state = .error("Screen recording permission required. Please grant permission in System Settings and try again.")
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
                guard let region = configuration.region else {
                    throw RecordingError.noRegionSelected
                }
                guard let display = content.displays.first else {
                    throw RecordingError.noDisplayAvailable
                }
                // Store region for frame processing and set display scale
                captureRegion = region
                displayScaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
                recordLogger.info("📐 Recording region: \(region.debugDescription), scale: \(self.displayScaleFactor)")
                
                // For region recording, we capture the full display and crop in post
                // This ensures we capture all content including windows
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

            case .voiceOnly:
                // Handled above
                return
            }

            // Configure stream
            let streamConfig = SCStreamConfiguration()

            // For region mode, use sourceRect to capture only the selected area
            if configuration.captureMode == .region, let region = captureRegion {
                // sourceRect is in points, SCStream will handle scaling
                streamConfig.sourceRect = region
                streamConfig.width = Int(region.width * displayScaleFactor)
                streamConfig.height = Int(region.height * displayScaleFactor)
                recordLogger.info("📐 Stream config: sourceRect=\(region.debugDescription), output=\(streamConfig.width)x\(streamConfig.height)")
            } else {
                streamConfig.width = Int(filter.contentRect.width * displayScaleFactor)
                streamConfig.height = Int(filter.contentRect.height * displayScaleFactor)
            }

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

            // Start webcam capture if enabled
            if configuration.enableWebcam {
                await startWebcamCapture()
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
    
    /// Reset recording service to idle state (for error recovery)
    func resetToIdle() {
        timer?.invalidate()
        timer = nil
        stream = nil
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        streamOutput = nil

        // Clear configuration state
        configuration.region = nil
        configuration.windowID = nil

        // Reset session state
        firstFrameTime = nil
        sessionStarted = false
        captureRegion = nil
        gifFrames = []

        state = .idle
        recordLogger.info("🔄 Recording service reset to idle")
    }

    /// Stop recording and return temp URL for preview (no save dialog)
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
        stopWebcamCapture()

        // Handle voice-only recording
        if configuration.captureMode == .voiceOnly {
            return try await stopVoiceOnlyRecordingForPreview()
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

        // Clear region capture state
        captureRegion = nil

        state = .idle
        
        // Verify the output file has content
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            recordLogger.info("📄 Final file size: \(fileSize) bytes")
            
            if fileSize == 0 {
                recordLogger.error("❌ Recording file is empty! This indicates recording failed.")
                throw RecordingError.outputFileEmpty
            }
        } catch {
            recordLogger.error("❌ Cannot verify output file: \(error)")
        }
        
        recordLogger.info("✅ Recording ready for preview: \(outputURL.path)")

        // Return temp URL - UI will show preview with save option
        return outputURL
    }

    /// Save the recording to user-selected location (called from preview)
    func saveRecording(tempURL: URL) async throws -> URL {
        recordLogger.info("💾 Saving recording from preview...")

        // Save using NSSavePanel for proper sandbox permissions
        let finalURL = try await saveRecordingWithPanel(tempURL: tempURL)

        recordLogger.info("✅ Recording saved to: \(finalURL.path)")

        // Also save to library for Collections view
        await saveToLibrary(url: finalURL)

        return finalURL
    }

    /// Delete temp recording file (if user cancels/discards from preview)
    func discardRecording(tempURL: URL) {
        recordLogger.info("🗑️ Discarding recording: \(tempURL.path)")
        try? FileManager.default.removeItem(at: tempURL)
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
        stopWebcamCapture()

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
        pixelBufferAdaptor = nil
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

    /// Stop voice-only recording and return temp URL for preview
    private func stopVoiceOnlyRecordingForPreview() async throws -> URL {
        audioRecorder?.stop()
        audioRecorder = nil

        guard let outputURL = currentFileURL else {
            throw RecordingError.noOutputFile
        }

        state = .idle
        recordLogger.info("✅ Voice recording ready for preview: \(outputURL.path)")

        // Return temp URL - UI will show preview with save option
        return outputURL
    }

    // MARK: - Frame Processing

    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard case .recording = state else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Get the pixel buffer from the sample buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            recordLogger.warning("⚠️ No image buffer in sample buffer")
            return
        }

        // Start asset writer session with first frame if not already started
        if !sessionStarted, let writer = assetWriter, writer.status == .writing {
            firstFrameTime = timestamp
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
            recordLogger.info("📹 Started asset writer session with first frame at \(CMTimeGetSeconds(timestamp))s")
        }

        if configuration.outputFormat == .gif {
            // Store frame for GIF encoding
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
        } else {
            // Write to video file using pixel buffer adaptor
            guard let adaptor = pixelBufferAdaptor,
                  let videoInput = videoInput,
                  videoInput.isReadyForMoreMediaData,
                  sessionStarted else {
                recordLogger.warning("⚠️ Cannot append frame. Ready: \(self.videoInput?.isReadyForMoreMediaData ?? false), SessionStarted: \(self.sessionStarted), Adaptor: \(self.pixelBufferAdaptor != nil)")
                return
            }

            // Append pixel buffer via adaptor for proper format handling
            if adaptor.append(imageBuffer, withPresentationTime: timestamp) {
                recordLogger.debug("📹 Appended video frame via adaptor")
            } else {
                if let writer = assetWriter {
                    recordLogger.warning("⚠️ Failed to append pixel buffer. Writer status: \(writer.status.rawValue), Error: \(writer.error?.localizedDescription ?? "none")")
                }
            }
        }
    }

    func processAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard case .recording = state,
              configuration.captureAudio,
              configuration.outputFormat.supportsAudio,
              sessionStarted else { return }

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

        // Video settings - use H.264 with proper settings for ScreenCaptureKit input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.quality.videoBitrate,
                AVVideoExpectedSourceFrameRateKey: configuration.frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ] as [String: Any]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        // Create pixel buffer adaptor for proper format conversion from ScreenCaptureKit
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

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

        guard let writer = assetWriter else {
            recordLogger.error("❌ Asset writer is nil!")
            return
        }

        let startResult = writer.startWriting()
        if !startResult {
            recordLogger.error("❌ Failed to start writing: \(writer.error?.localizedDescription ?? "Unknown error")")
            return
        }

        // Don't start session here - will start with first frame timestamp
        sessionStarted = false
        firstFrameTime = nil
        recordLogger.info("✅ Asset writer initialized with pixel buffer adaptor - waiting for first frame")
    }

    private func finalizeAssetWriter() async {
        guard let writer = assetWriter else {
            recordLogger.error("❌ No asset writer to finalize")
            return
        }
        
        recordLogger.info("🔄 Finalizing asset writer...")
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let writerStatus = writer.status
            let writerError = writer.error
            
            writer.finishWriting {
                Task { @MainActor in
                    switch writer.status {
                    case .failed:
                        recordLogger.error("❌ Asset writer failed: \(writerError?.localizedDescription ?? "Unknown error")")
                    case .completed:
                        recordLogger.info("✅ Asset writer completed successfully")
                    case .cancelled:
                        recordLogger.warning("⚠️ Asset writer was cancelled")
                    default:
                        recordLogger.info("✅ Asset writer finalized with status: \(writer.status.rawValue)")
                    }
                    continuation.resume()
                }
            }
        }

        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
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

    // MARK: - Webcam Capture

    private func startWebcamCapture() async {
        recordLogger.info("📹 Starting webcam capture...")

        // Check camera permission
        let hasPermission = await CameraPermission.checkAndRequest()
        guard hasPermission else {
            recordLogger.warning("⚠️ Camera permission denied, skipping webcam")
            return
        }

        // Create webcam manager
        webcamManager = WebcamCaptureManager()

        do {
            try webcamManager?.startCapture()
            recordLogger.info("✅ Webcam capture started")

            // Show webcam preview window
            showWebcamPreview()
        } catch {
            recordLogger.error("❌ Failed to start webcam: \(error.localizedDescription)")
            webcamManager = nil
        }
    }

    private func stopWebcamCapture() {
        webcamManager?.stopCapture()
        webcamManager = nil
        hideWebcamPreview()
        recordLogger.info("📹 Webcam capture stopped")
    }

    private func showWebcamPreview() {
        let position = configuration.webcamPosition
        let size = configuration.webcamSize

        webcamPreviewWindow = WebcamPreviewWindowController(
            position: position,
            size: size,
            webcamManager: webcamManager!
        )
        webcamPreviewWindow?.showWindow(nil)
    }

    private func hideWebcamPreview() {
        webcamPreviewWindow?.close()
        webcamPreviewWindow = nil
    }

    /// Get current webcam frame for compositing (if enabled)
    func getCurrentWebcamFrame() -> CGImage? {
        return webcamManager?.currentFrame
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

// MARK: - Webcam Capture Manager
class WebcamCaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.instinctly.webcam.session")

    @Published var currentFrame: CGImage?
    @Published var isCapturing = false

    override init() {
        super.init()
        recordLogger.info("📹 WebcamCaptureManager initialized")
    }
    
    deinit {
        recordLogger.info("📹 WebcamCaptureManager deinitializing...")
        stopCapture()
    }

    func startCapture() throws {
        recordLogger.info("📹 Starting webcam capture session...")
        
        // Ensure we're starting fresh
        stopCapture()
        
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        
        // Get default video device (FaceTime camera)
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            recordLogger.error("❌ No video device available")
            throw WebcamError.noDeviceAvailable
        }

        recordLogger.info("📹 Using video device: \(videoDevice.localizedName)")

        do {
            // Create input
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(videoInput) else {
                throw WebcamError.cannotAddInput
            }
            session.addInput(videoInput)

            // Create output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: sessionQueue)
            
            // Prevent frame drops to avoid crashes
            output.alwaysDiscardsLateVideoFrames = true

            guard session.canAddOutput(output) else {
                throw WebcamError.cannotAddOutput
            }
            session.addOutput(output)
            
            // Store references only after successful setup
            self.captureSession = session
            self.videoOutput = output

            // Start capture on background queue with proper error handling
            sessionQueue.async { [weak self] in
                guard let self = self, let session = self.captureSession else { return }
                
                do {
                    if !session.isRunning {
                        session.startRunning()
                        DispatchQueue.main.async {
                            self.isCapturing = true
                            recordLogger.info("✅ Webcam capture session started")
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        recordLogger.error("❌ Failed to start webcam session: \(error)")
                        self.stopCapture()
                    }
                }
            }
        } catch {
            recordLogger.error("❌ Failed to setup webcam: \(error)")
            throw error
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
                
                // Remove all inputs and outputs to prevent crashes
                for input in session.inputs {
                    session.removeInput(input)
                }
                for output in session.outputs {
                    session.removeOutput(output)
                }
            }
            
            DispatchQueue.main.async {
                self.isCapturing = false
                self.currentFrame = nil
                self.captureSession = nil
                self.videoOutput = nil
                recordLogger.info("📹 Webcam capture session stopped and cleaned up")
            }
        }
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Early return if not capturing to prevent unnecessary processing
        guard isCapturing else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Use autoreleasepool to manage memory properly
        autoreleasepool {
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            
            // Use a static context to avoid creating new contexts repeatedly
            let context = CIContext(options: [.useSoftwareRenderer: false])

            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                DispatchQueue.main.async { [weak self] in
                    // Only update if still capturing to avoid race conditions
                    guard let self = self, self.isCapturing else { return }
                    self.currentFrame = cgImage
                }
            }
        }
    }
}

// MARK: - Webcam Errors
enum WebcamError: LocalizedError {
    case noDeviceAvailable
    case cannotAddInput
    case cannotAddOutput
    case captureSessionFailed

    var errorDescription: String? {
        switch self {
        case .noDeviceAvailable: return "No webcam device available"
        case .cannotAddInput: return "Cannot add video input to capture session"
        case .cannotAddOutput: return "Cannot add video output to capture session"
        case .captureSessionFailed: return "Webcam capture session failed"
        }
    }
}

// MARK: - Webcam Preview Window
import SwiftUI

class WebcamPreviewWindowController: NSWindowController {
    private var webcamManager: WebcamCaptureManager

    init(position: RecordingConfiguration.WebcamPosition, size: RecordingConfiguration.WebcamSize, webcamManager: WebcamCaptureManager) {
        self.webcamManager = webcamManager

        // Calculate window size based on configuration
        let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)
        let webcamWidth = screenSize.width * size.percentage
        let webcamHeight = webcamWidth * 0.75 // 4:3 aspect ratio

        // Calculate position
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let alignment = position.alignment
        let x = screenFrame.origin.x + (screenFrame.width - webcamWidth) * alignment.x
        let y = screenFrame.origin.y + (screenFrame.height - webcamHeight) * alignment.y

        let windowRect = CGRect(x: x, y: y, width: webcamWidth, height: webcamHeight)

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        super.init(window: window)

        // Add SwiftUI view
        let hostingView = NSHostingView(rootView: WebcamPreviewView(webcamManager: webcamManager))
        window.contentView = hostingView

        recordLogger.info("📹 Webcam preview window created at position: \(position.rawValue)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Webcam Preview View
struct WebcamPreviewView: View {
    @ObservedObject var webcamManager: WebcamCaptureManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with rounded corners
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                // Webcam feed
                if let frame = webcamManager.currentFrame {
                    Image(decorative: frame, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(x: -1, y: 1) // Mirror the image
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Loading state
                    VStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Camera")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Recording indicator
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Spacer()
                    }
                    .padding(8)
                    Spacer()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
        }
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
    case alreadyRecording
    case outputFileEmpty

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
        case .alreadyRecording: return "Recording is already in progress"
        case .outputFileEmpty: return "Recording file is empty - recording may have failed"
        }
    }
}

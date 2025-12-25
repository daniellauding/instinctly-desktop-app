import AppKit
import ScreenCaptureKit
import CoreGraphics
import Combine
import os.log

private let captureLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "ScreenCapture")

/// Service for capturing screenshots using ScreenCaptureKit
class ScreenCaptureService: ObservableObject {
    @Published var isAuthorized: Bool = false
    @Published var availableWindows: [SCWindow] = []
    @Published var availableDisplays: [SCDisplay] = []

    static let shared = ScreenCaptureService()

    init() {
        captureLogger.info("🎬 ScreenCaptureService initialized")
        Task {
            await checkPermission()
        }
    }

    // MARK: - Permission

    @MainActor
    func checkPermission() async {
        captureLogger.info("🔐 Checking screen capture permission...")
        do {
            let content = try await SCShareableContent.current
            isAuthorized = true
            availableDisplays = content.displays
            availableWindows = content.windows.filter { $0.isOnScreen }
            captureLogger.info("✅ Permission granted. Displays: \(content.displays.count), Windows: \(self.availableWindows.count)")
        } catch {
            isAuthorized = false
            captureLogger.error("❌ Permission check failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    func requestPermission() async {
        captureLogger.info("🔐 Requesting screen capture permission...")
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await checkPermission()
        } catch {
            captureLogger.error("❌ Screen capture permission denied: \(error.localizedDescription)")
        }
    }

    // MARK: - Capture Methods

    /// Capture the entire screen
    func captureFullScreen() async throws -> NSImage {
        captureLogger.info("📸 Starting full screen capture...")

        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            captureLogger.error("❌ No display available")
            throw CaptureError.noDisplayAvailable
        }

        captureLogger.info("📺 Capturing display: \(display.width)x\(display.height)")

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width) * 2
        config.height = Int(display.height) * 2
        config.scalesToFit = false
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        captureLogger.info("✅ Full screen captured successfully")
        return NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
    }

    /// Capture a specific window
    func captureWindow(_ window: SCWindow? = nil) async throws -> NSImage {
        captureLogger.info("🪟 Starting window capture...")

        let content = try await SCShareableContent.current

        let targetWindow: SCWindow
        if let window = window {
            targetWindow = window
        } else {
            guard let frontWindow = content.windows
                .filter({ $0.isOnScreen && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier })
                .first else {
                captureLogger.error("❌ No window available")
                throw CaptureError.noWindowAvailable
            }
            targetWindow = frontWindow
        }

        captureLogger.info("🪟 Capturing window: \(targetWindow.title ?? "Untitled") (\(targetWindow.frame.width)x\(targetWindow.frame.height))")

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let config = SCStreamConfiguration()
        config.width = Int(targetWindow.frame.width) * 2
        config.height = Int(targetWindow.frame.height) * 2
        config.scalesToFit = false
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        captureLogger.info("✅ Window captured successfully")
        return NSImage(cgImage: image, size: targetWindow.frame.size)
    }

    // Retain the window controller to prevent deallocation
    private var regionController: RegionSelectionWindowController?

    /// Capture a user-selected region with interactive overlay
    @MainActor
    func captureRegion() async throws -> NSImage {
        captureLogger.info("🎯 Starting region capture...")

        // First capture full screen
        captureLogger.info("📸 Capturing full screen for background...")
        let fullScreenImage: NSImage
        do {
            fullScreenImage = try await captureFullScreen()
            captureLogger.info("✅ Background captured: \(fullScreenImage.size.width)x\(fullScreenImage.size.height)")
        } catch {
            captureLogger.error("❌ Failed to capture background: \(error.localizedDescription)")
            throw error
        }

        // Show region selection overlay with the captured screen as background
        captureLogger.info("🖼️ Showing region selection overlay...")

        return try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<NSImage, Error>) in
            // Track if we've already resumed to prevent double-resume crashes
            var hasResumed = false
            let resumeLock = NSLock()

            func safeResume(with result: Result<NSImage, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard !hasResumed else {
                    captureLogger.warning("⚠️ Attempted to resume continuation twice - ignoring")
                    return
                }
                hasResumed = true

                switch result {
                case .success(let image):
                    captureLogger.info("✅ Resuming continuation with image")
                    continuation.resume(returning: image)
                case .failure(let error):
                    captureLogger.error("❌ Resuming continuation with error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }

            let controller = RegionSelectionWindowController(
                backgroundImage: fullScreenImage,
                onSelection: { [weak self] rect in
                    captureLogger.info("📐 Selection received: \(rect.debugDescription)")
                    captureLogger.info("📐 Image size: \(fullScreenImage.size.width)x\(fullScreenImage.size.height)")

                    // Clear controller reference
                    DispatchQueue.main.async {
                        self?.regionController = nil
                    }

                    // Rect is already in points (same coordinate system as image.size)
                    // cropImage handles the scaling to pixels internally
                    captureLogger.info("✂️ Cropping to rect: \(rect.debugDescription)")

                    if let croppedImage = ImageProcessingService.cropImage(fullScreenImage, to: rect) {
                        captureLogger.info("✅ Image cropped successfully: \(croppedImage.size.width)x\(croppedImage.size.height)")
                        safeResume(with: .success(croppedImage))
                    } else {
                        captureLogger.error("❌ Failed to crop image")
                        safeResume(with: .failure(CaptureError.cropFailed))
                    }
                },
                onCancel: { [weak self] in
                    captureLogger.info("❌ Region selection cancelled")
                    DispatchQueue.main.async {
                        self?.regionController = nil
                    }
                    safeResume(with: .failure(CaptureError.selectionCancelled))
                }
            )

            self?.regionController = controller

            // Show the window
            captureLogger.info("📺 Displaying selection window...")
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            captureLogger.info("✅ Selection window displayed, waiting for user input...")
        }
    }

    /// Alternative: Interactive region capture using screencapture command
    /// Note: May not work in sandboxed apps or can cause UI issues
    func captureRegionInteractive() async throws -> NSImage {
        captureLogger.info("🖥️ Starting interactive region capture (screencapture command)...")

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("instinctly_capture_\(UUID().uuidString).png")
        captureLogger.info("📁 Temp file: \(tempFile.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", tempFile.path]

        let captureProcess = process

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        captureLogger.info("🚀 Running screencapture process...")
                        try captureProcess.run()
                        captureProcess.waitUntilExit()

                        if Task.isCancelled {
                            captureLogger.info("⚠️ Task was cancelled")
                            try? FileManager.default.removeItem(at: tempFile)
                            continuation.resume(throwing: CaptureError.selectionCancelled)
                            return
                        }

                        captureLogger.info("📊 Process exited with status: \(captureProcess.terminationStatus)")

                        guard captureProcess.terminationStatus == 0,
                              FileManager.default.fileExists(atPath: tempFile.path),
                              let image = NSImage(contentsOf: tempFile) else {
                            captureLogger.error("❌ Capture failed or file not found")
                            try? FileManager.default.removeItem(at: tempFile)
                            continuation.resume(throwing: CaptureError.selectionCancelled)
                            return
                        }

                        captureLogger.info("✅ Interactive capture successful")
                        try? FileManager.default.removeItem(at: tempFile)
                        continuation.resume(returning: image)
                    } catch {
                        captureLogger.error("❌ Process error: \(error.localizedDescription)")
                        try? FileManager.default.removeItem(at: tempFile)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            captureLogger.info("⚠️ Cancelling screencapture process")
            if captureProcess.isRunning {
                captureProcess.terminate()
            }
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    // MARK: - Window Picker

    func getAvailableWindows() async -> [SCWindow] {
        captureLogger.info("🪟 Getting available windows...")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier &&
                $0.frame.width > 100 && $0.frame.height > 100
            }
            captureLogger.info("✅ Found \(windows.count) available windows")
            return windows
        } catch {
            captureLogger.error("❌ Failed to get windows: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Capture Window Selector

import SwiftUI

@MainActor
class CaptureWindowSelector {
    private var activeController: CaptureWindowSelectionController?

    func selectWindow() async -> SCWindow? {
        captureLogger.info("🪟 Starting capture window selection")

        return await withCheckedContinuation { continuation in
            var hasResumed = false

            let controller = CaptureWindowSelectionController { [weak self] result in
                guard !hasResumed else {
                    captureLogger.warning("⚠️ Continuation already resumed, ignoring")
                    return
                }
                hasResumed = true
                captureLogger.info("✅ Window selection complete: \(result?.title ?? "cancelled")")
                self?.activeController = nil
                continuation.resume(returning: result)
            }

            self.activeController = controller
            controller.show()
        }
    }
}

// MARK: - Capture Window Selection Controller
@MainActor
class CaptureWindowSelectionController: NSWindowController {
    private var onComplete: ((SCWindow?) -> Void)?
    private var hasClosed = false

    convenience init(onComplete: @escaping (SCWindow?) -> Void) {
        captureLogger.info("🎯 Initializing CaptureWindowSelectionController")

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Select Window to Capture"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        self.init(window: panel)
        self.onComplete = onComplete

        let hostingView = NSHostingView(rootView: CaptureWindowSelectionView(
            onSelect: { [weak self] scWindow in
                self?.handleComplete(scWindow)
            },
            onCancel: { [weak self] in
                self?.handleComplete(nil)
            }
        ))
        panel.contentView = hostingView

        // Center on screen
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 210
            let y = screen.visibleFrame.midY - 250
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        captureLogger.info("✅ CaptureWindowSelectionController initialized")
    }

    func show() {
        captureLogger.info("📺 Showing capture window selection")
        showWindow(nil)
        window?.orderFrontRegardless()
        window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleComplete(_ result: SCWindow?) {
        guard !hasClosed else { return }
        hasClosed = true

        captureLogger.info("🎬 Closing window picker")
        window?.orderOut(nil)
        close()

        let completion = onComplete
        onComplete = nil

        DispatchQueue.main.async {
            completion?(result)
        }
    }
}

// MARK: - Capture Window Selection View
struct CaptureWindowSelectionView: View {
    let onSelect: (SCWindow) -> Void
    let onCancel: () -> Void

    @State private var windows: [(window: SCWindow, title: String, appName: String, icon: NSImage?)] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "macwindow")
                    .foregroundColor(.blue)
                Text("Select Window to Capture")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()

            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading windows...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No windows available")
                        .foregroundColor(.secondary)
                    Text("Open an application window and try again")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(windows, id: \.window.windowID) { item in
                            CaptureWindowRow(
                                title: item.title,
                                appName: item.appName,
                                icon: item.icon
                            ) {
                                onSelect(item.window)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(20)
        .frame(width: 400, height: 450)
        .onAppear {
            loadWindows()
        }
    }

    private func loadWindows() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let windowList = content.windows.compactMap { window -> (window: SCWindow, title: String, appName: String, icon: NSImage?)? in
                    guard let title = window.title, !title.isEmpty,
                          window.frame.width > 50, window.frame.height > 50,
                          let app = window.owningApplication,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                        return nil
                    }
                    let appName = app.applicationName
                    let icon = NSRunningApplication(processIdentifier: app.processID)?.icon
                    return (window, title, appName, icon)
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

// MARK: - Capture Window Row
struct CaptureWindowRow: View {
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
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "macwindow")
                        .font(.title2)
                        .frame(width: 36, height: 36)
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

                Image(systemName: "camera.fill")
                    .foregroundColor(.blue)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(10)
            .background(isHovered ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Capture Errors
enum CaptureError: LocalizedError {
    case noDisplayAvailable
    case noWindowAvailable
    case selectionCancelled
    case cropFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available for capture"
        case .noWindowAvailable: return "No window available for capture"
        case .selectionCancelled: return "Selection was cancelled"
        case .cropFailed: return "Failed to crop image"
        case .permissionDenied: return "Screen capture permission denied"
        }
    }
}

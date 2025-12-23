import AppKit
import SwiftUI
import Carbon.HIToolbox
import os.log

private let appLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyboardShortcutManager: KeyboardShortcutManager?
    private var screenCaptureService: ScreenCaptureService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLogger.info("🚀 Application did finish launching")

        // Apply dock visibility preference (default to true if not set)
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        appLogger.info("📱 Dock visibility: \(showInDock)")

        // Initialize services
        screenCaptureService = ScreenCaptureService()
        keyboardShortcutManager = KeyboardShortcutManager()

        // Setup global shortcuts (respects user setting)
        setupGlobalShortcuts()
        
        // Listen for shortcuts setting changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(globalShortcutsSettingChanged(_:)),
            name: NSNotification.Name("GlobalShortcutsEnabledChanged"),
            object: nil
        )

        // Request screen capture permission if needed
        Task {
            await screenCaptureService?.requestPermission()
        }

        appLogger.info("✅ Application setup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        appLogger.info("👋 Application will terminate")
        keyboardShortcutManager?.unregisterAll()

        // Kill any running screencapture processes to prevent screen blocking
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-9", "screencapture"]
        try? killProcess.run()
    }

    private func setupGlobalShortcuts() {
        // Check if global shortcuts are enabled (default disabled for safety)
        let globalShortcutsEnabled = UserDefaults.standard.bool(forKey: "globalShortcutsEnabled")
        
        if !globalShortcutsEnabled {
            appLogger.info("⌨️ Global shortcuts disabled by user setting")
            keyboardShortcutManager?.unregisterAll()
            return
        }
        
        appLogger.info("⌨️ Setting up global shortcuts...")

        // Cmd+Shift+3: Full screen capture
        keyboardShortcutManager?.register(
            keyCode: kVK_ANSI_3,
            modifiers: [.command, .shift]
        ) { [weak self] in
            appLogger.info("⌨️ Cmd+Shift+3 pressed - Full screen capture")
            self?.captureFullScreen()
        }

        // Cmd+Shift+4: Region capture
        keyboardShortcutManager?.register(
            keyCode: kVK_ANSI_4,
            modifiers: [.command, .shift]
        ) { [weak self] in
            appLogger.info("⌨️ Cmd+Shift+4 pressed - Region capture")
            self?.captureRegion()
        }

        // Cmd+Shift+5: Window capture
        keyboardShortcutManager?.register(
            keyCode: kVK_ANSI_5,
            modifiers: [.command, .shift]
        ) { [weak self] in
            appLogger.info("⌨️ Cmd+Shift+5 pressed - Window capture")
            self?.captureWindow()
        }

        // Cmd+Shift+6: Open from clipboard
        keyboardShortcutManager?.register(
            keyCode: kVK_ANSI_6,
            modifiers: [.command, .shift]
        ) { [weak self] in
            appLogger.info("⌨️ Cmd+Shift+6 pressed - Open from clipboard")
            self?.openFromClipboard()
        }

        appLogger.info("✅ Global shortcuts registered")
    }
    
    @objc private func globalShortcutsSettingChanged(_ notification: Notification) {
        appLogger.info("⚙️ Global shortcuts setting changed")
        setupGlobalShortcuts()
    }
    
    // MARK: - URL Handling
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }
    
    private func handleURL(_ url: URL) {
        appLogger.info("🔗 Handling URL: \(url.absoluteString)")
        
        guard url.scheme == "instinctly" else {
            appLogger.error("❌ Invalid scheme: \(url.scheme ?? "nil")")
            return
        }
        
        switch url.host {
        case "editor":
            // Open editor with current image
            appLogger.info("📝 Opening editor via URL")
            if AppState.shared.currentImage != nil {
                // Open editor window
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openEditorWindow, object: nil)
            }
            
        case "share":
            // Handle share URL (e.g., instinctly://share/RECORD_ID)
            let shareId = url.pathComponents.dropFirst().first ?? ""
            appLogger.info("🔗 Opening share: \(shareId)")
            
        default:
            appLogger.info("❌ Unknown URL host: \(url.host ?? "nil")")
        }
    }

    // MARK: - Capture Actions

    @MainActor
    private func captureFullScreen() {
        appLogger.info("📸 Starting full screen capture...")
        Task {
            do {
                guard let image = try await screenCaptureService?.captureFullScreen() else {
                    appLogger.error("❌ Full screen capture returned nil")
                    return
                }
                appLogger.info("✅ Full screen captured: \(image.size.width)x\(image.size.height)")
                openEditor(with: image)
            } catch {
                appLogger.error("❌ Full screen capture failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func captureRegion() {
        appLogger.info("🎯 Starting region capture...")
        Task {
            AppState.shared.isCapturing = true
            appLogger.info("📌 isCapturing = true")

            do {
                guard let image = try await screenCaptureService?.captureRegion() else {
                    appLogger.error("❌ Region capture returned nil")
                    AppState.shared.isCapturing = false
                    return
                }
                appLogger.info("✅ Region captured: \(image.size.width)x\(image.size.height)")
                AppState.shared.isCapturing = false
                openEditor(with: image)
            } catch {
                appLogger.error("❌ Region capture failed: \(error.localizedDescription)")
                AppState.shared.isCapturing = false
            }
        }
    }

    @MainActor
    private func captureWindow() {
        appLogger.info("🪟 Starting window capture...")
        Task {
            do {
                guard let image = try await screenCaptureService?.captureWindow() else {
                    appLogger.error("❌ Window capture returned nil")
                    return
                }
                appLogger.info("✅ Window captured: \(image.size.width)x\(image.size.height)")
                openEditor(with: image)
            } catch {
                appLogger.error("❌ Window capture failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func openFromClipboard() {
        appLogger.info("📋 Opening from clipboard...")

        guard let pasteboard = NSPasteboard.general.data(forType: .tiff),
              let image = NSImage(data: pasteboard) else {
            // Try PNG
            guard let pngData = NSPasteboard.general.data(forType: .png),
                  let image = NSImage(data: pngData) else {
                appLogger.warning("⚠️ No image found in clipboard")
                return
            }
            appLogger.info("✅ Loaded PNG from clipboard: \(image.size.width)x\(image.size.height)")
            openEditor(with: image)
            return
        }
        appLogger.info("✅ Loaded TIFF from clipboard: \(image.size.width)x\(image.size.height)")
        openEditor(with: image)
    }

    @MainActor
    private func openEditor(with image: NSImage) {
        appLogger.info("🖼️ Opening editor with image: \(image.size.width)x\(image.size.height)")

        AppState.shared.currentImage = image
        AppState.shared.annotations = []

        // Open editor window
        if let url = URL(string: "instinctly://editor") {
            appLogger.info("🔗 Opening URL: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
        }

        // Alternative: Use environment to open window
        NotificationCenter.default.post(name: .openEditorWindow, object: image)
        appLogger.info("📤 Posted openEditorWindow notification")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openEditorWindow = Notification.Name("openEditorWindow")
    static let captureRegion = Notification.Name("captureRegion")
    static let captureFullScreen = Notification.Name("captureFullScreen")
    static let captureWindow = Notification.Name("captureWindow")
}

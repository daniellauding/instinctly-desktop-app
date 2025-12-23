import Foundation
import ScreenCaptureKit
import AppKit

/// Helper to request and check screen recording permissions
@MainActor
class ScreenRecordingPermission {
    
    /// Check if we have screen recording permission
    static func hasPermission() async -> Bool {
        do {
            // This will return false if we don't have permission
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }
    
    /// Request screen recording permission (triggers system prompt)
    static func requestPermission() {
        Task { @MainActor in
            do {
                // This will trigger the system permission dialog if not already granted
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                print("✅ Screen recording permission granted")
            } catch {
                print("❌ Screen recording permission check failed: \(error)")
                
                // Show alert to guide user - already on main actor
                showPermissionAlert()
            }
        }
    }
    
    /// Show alert guiding user to grant permission
    static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Instinctly needs screen recording permission to capture your screen.\n\n1. Click 'Open System Settings'\n2. Enable Instinctly in Screen Recording\n3. Restart Instinctly"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Screen Recording
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Check permission and request if needed
    static func checkAndRequest() async {
        if await !hasPermission() {
            requestPermission()
        }
    }
}
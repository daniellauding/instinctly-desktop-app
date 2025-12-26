import Foundation
import AVFoundation
import AppKit

/// Helper to request and check camera/webcam permissions
@MainActor
class CameraPermission {
    
    /// Check if we have camera permission
    static func hasPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    /// Request camera permission
    static func requestPermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("📹 Camera permission status: \(currentStatus.rawValue)")
        
        switch currentStatus {
        case .authorized:
            print("📹 Camera already authorized")
            return true
            
        case .notDetermined:
            print("📹 Requesting camera permission...")
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    print("📹 Camera permission request result: \(granted)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: granted)
                    }
                }
            }
            
        case .denied, .restricted:
            print("📹 Camera permission denied/restricted")
            showPermissionAlert()
            return false
            
        @unknown default:
            print("📹 Unknown camera permission status")
            return false
        }
    }
    
    /// Show alert guiding user to grant permission
    static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Camera Permission Required"
        alert.informativeText = "Instinctly needs camera permission to record with webcam overlay.\n\n1. Click 'Open System Settings'\n2. Enable Camera for Instinctly\n3. Restart Instinctly"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Camera
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Check permission and request if needed
    static func checkAndRequest() async -> Bool {
        if hasPermission() {
            return true
        }
        return await requestPermission()
    }
}
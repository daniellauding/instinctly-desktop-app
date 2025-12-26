#!/usr/bin/env swift

import AppKit
import SwiftUI

// Create a test video file
let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("Instinctly_2025-12-22_13-02-28.mp4")

// Show the preview panel
class TestApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a simple window with a button to trigger preview
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        let button = NSButton(title: "Show Recording Preview", target: nil, action: nil)
        button.frame = NSRect(x: 50, y: 50, width: 200, height: 40)
        button.action = #selector(showPreview)
        button.target = self
        
        window.contentView?.addSubview(button)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func showPreview() {
        // Open the file in QuickTime
        NSWorkspace.shared.open(testURL)
        print("Opening: \(testURL.path)")
    }
}

let app = NSApplication.shared
let delegate = TestApp()
app.delegate = delegate
app.run()
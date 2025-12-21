import SwiftUI
import AppKit
import os.log

private let regionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Instinctly", category: "RegionSelection")

// MARK: - Custom Window that can become key/main
private class RegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A fullscreen overlay window for interactive region selection
class RegionSelectionWindowController: NSWindowController {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var hasClosed = false
    private var safetyTimer: Timer?

    convenience init(backgroundImage: NSImage? = nil, onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        regionLogger.info("🎯 Initializing RegionSelectionWindowController")

        guard let screen = NSScreen.main else {
            regionLogger.error("❌ No main screen available")
            // Call cancel immediately if no screen
            DispatchQueue.main.async { onCancel() }
            self.init(window: nil)
            return
        }

        regionLogger.info("📐 Screen frame: \(screen.frame.debugDescription)")

        let window = RegionSelectionWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Use very high window level to ensure we're above everything
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false

        regionLogger.info("✅ Window created with level: \(window.level.rawValue)")

        self.init(window: window)
        self.onSelection = onSelection
        self.onCancel = onCancel

        let contentView = RegionSelectionNSView(
            backgroundImage: backgroundImage,
            onConfirm: { [weak self] rect in
                regionLogger.info("✅ Selection confirmed: \(rect.debugDescription)")
                self?.handleSelection(rect)
            },
            onCancel: { [weak self] in
                regionLogger.info("❌ Selection cancelled by user")
                self?.handleCancel()
            }
        )

        window.contentView = contentView
        window.setFrame(screen.frame, display: true)

        // Safety timeout - auto-cancel after 60 seconds to prevent infinite hang
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            regionLogger.warning("⚠️ Safety timeout triggered - cancelling selection")
            self?.handleCancel()
        }

        regionLogger.info("✅ RegionSelectionWindowController initialized")
    }

    override func showWindow(_ sender: Any?) {
        regionLogger.info("📺 showWindow called")
        super.showWindow(sender)

        guard let window = window else {
            regionLogger.error("❌ Window is nil in showWindow")
            handleCancel()
            return
        }

        // Ensure window is visible and accepts input
        window.orderFrontRegardless()
        window.makeKey()
        window.makeMain()

        // Force app to front
        NSApp.activate(ignoringOtherApps: true)

        regionLogger.info("✅ Window shown and activated")
    }

    private func handleSelection(_ rect: CGRect) {
        guard !hasClosed else {
            regionLogger.warning("⚠️ handleSelection called but already closed")
            return
        }
        hasClosed = true
        safetyTimer?.invalidate()
        safetyTimer = nil

        regionLogger.info("🎬 Closing window and calling onSelection")

        // Close window first
        window?.orderOut(nil)
        close()

        // Call callback on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onSelection?(rect)
        }
    }

    private func handleCancel() {
        guard !hasClosed else {
            regionLogger.warning("⚠️ handleCancel called but already closed")
            return
        }
        hasClosed = true
        safetyTimer?.invalidate()
        safetyTimer = nil

        regionLogger.info("🎬 Closing window and calling onCancel")

        // Close window first
        window?.orderOut(nil)
        close()

        // Call callback on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
    }

    deinit {
        regionLogger.info("🗑️ RegionSelectionWindowController deallocated")
        safetyTimer?.invalidate()
    }
}

// MARK: - NSView-based implementation (more reliable than SwiftUI for overlay)
class RegionSelectionNSView: NSView {
    private var backgroundImage: NSImage?
    private var onConfirm: ((CGRect) -> Void)?
    private var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isDragging = false
    private var eventMonitor: Any?

    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    init(backgroundImage: NSImage?, onConfirm: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.backgroundImage = backgroundImage
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(frame: .zero)

        regionLogger.info("🎨 RegionSelectionNSView initialized")
        setupEventMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEventMonitor() {
        // Monitor for ESC key
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC
                regionLogger.info("⌨️ ESC pressed - cancelling")
                self?.onCancel?()
                return nil
            }
            return event
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        regionLogger.info("🎯 View became first responder")
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        regionLogger.info("📺 View moved to window, became first responder")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            regionLogger.error("❌ No graphics context available")
            return
        }

        let bounds = self.bounds

        // Draw background image
        if let image = backgroundImage {
            image.draw(in: bounds)
        } else {
            // Fallback to dark background
            NSColor.black.setFill()
            bounds.fill()
        }

        // Draw semi-transparent overlay
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        // Cut out the selection area (if any)
        if let rect = selectionRect {
            // Clear the selection area to show the image underneath
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            // Redraw the image in the selection area
            if let image = backgroundImage {
                context.saveGState()
                context.clip(to: rect)
                image.draw(in: bounds)
                context.restoreGState()
            }

            // Draw selection border
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2
            borderPath.stroke()

            // Draw dimensions
            let dimensionText = "\(Int(rect.width)) × \(Int(rect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let textSize = dimensionText.size(withAttributes: attributes)
            let textRect = CGRect(
                x: rect.midX - textSize.width / 2 - 8,
                y: rect.maxY + 8,
                width: textSize.width + 16,
                height: textSize.height + 8
            )

            // Background for text
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()

            // Draw text
            let textPoint = CGPoint(x: textRect.origin.x + 8, y: textRect.origin.y + 4)
            dimensionText.draw(at: textPoint, withAttributes: attributes)
        }

        // Draw instructions if not dragging
        if !isDragging && selectionRect == nil {
            drawInstructions(in: bounds)
        }
    }

    private func drawInstructions(in bounds: CGRect) {
        let text = "Drag to select region • ESC to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: bounds.midX - textSize.width / 2 - 20,
            y: bounds.midY - textSize.height / 2 - 10,
            width: textSize.width + 40,
            height: textSize.height + 20
        )

        // Background
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: textRect, xRadius: 10, yRadius: 10).fill()

        // Text
        let textPoint = CGPoint(x: textRect.origin.x + 20, y: textRect.origin.y + 10)
        text.draw(at: textPoint, withAttributes: attributes)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        regionLogger.info("🖱️ mouseDown at: \(point.debugDescription)")

        startPoint = point
        currentPoint = point
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        regionLogger.info("🖱️ mouseUp at: \(point.debugDescription)")

        currentPoint = point
        isDragging = false

        // AUTO-CAPTURE: Immediately capture when mouse is released
        if let rect = selectionRect, rect.width > 10 && rect.height > 10 {
            regionLogger.info("✅ Valid selection, auto-capturing: \(rect.debugDescription)")

            // Convert to screen coordinates (flip Y since NSView has origin at bottom-left)
            let flippedRect = CGRect(
                x: rect.origin.x,
                y: bounds.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )

            onConfirm?(flippedRect)
        } else {
            regionLogger.info("⚠️ Selection too small, resetting")
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        regionLogger.info("🖱️ Right-click - cancelling")
        onCancel?()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        regionLogger.info("🗑️ RegionSelectionNSView deallocated")
    }
}

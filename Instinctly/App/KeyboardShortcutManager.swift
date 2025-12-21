import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts using CGEvent tap
class KeyboardShortcutManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcuts: [ShortcutKey: () -> Void] = [:]

    struct ShortcutKey: Hashable {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers.rawValue)
        }

        static func == (lhs: ShortcutKey, rhs: ShortcutKey) -> Bool {
            lhs.keyCode == rhs.keyCode &&
            lhs.modifiers.intersection([.command, .shift, .option, .control]) ==
            rhs.modifiers.intersection([.command, .shift, .option, .control])
        }
    }

    init() {
        setupEventTap()
    }

    deinit {
        unregisterAll()
    }

    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        let key = ShortcutKey(keyCode: keyCode, modifiers: modifiers)
        shortcuts[key] = action
    }

    func unregister(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        let key = ShortcutKey(keyCode: keyCode, modifiers: modifiers)
        shortcuts.removeValue(forKey: key)
    }

    func unregisterAll() {
        shortcuts.removeAll()
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }

            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Check accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }

        let key = ShortcutKey(keyCode: keyCode, modifiers: modifiers)

        if let action = shortcuts[key] {
            DispatchQueue.main.async {
                action()
            }
            return nil // Consume the event
        }

        return Unmanaged.passRetained(event)
    }
}

// MARK: - Common Key Codes
extension KeyboardShortcutManager {
    static let keyCode1 = kVK_ANSI_1
    static let keyCode2 = kVK_ANSI_2
    static let keyCode3 = kVK_ANSI_3
    static let keyCode4 = kVK_ANSI_4
    static let keyCode5 = kVK_ANSI_5
    static let keyCode6 = kVK_ANSI_6
}

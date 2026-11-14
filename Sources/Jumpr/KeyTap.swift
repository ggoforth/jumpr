import AppKit
import JumprCore

/// Session-level key listener. Idle: looks only for the two shortcuts (labels and scroll
/// mode) and passes everything else through. Capturing: plain keys go to `onKey`, which
/// decides whether to swallow.
/// The handler runs on the main run loop and must never block: no AX calls, no scans.
final class KeyTap {
    var hotkey: Hotkey = .default
    var scrollHotkey: Hotkey = .defaultScroll
    /// True while something else needs the keyboard untouched (e.g. the hotkey recorder).
    var suspended = false
    /// True while Jumpr is paused: the shortcuts are ignored and nothing is captured.
    /// Separate from `suspended`, which the hotkey recorder owns.
    var paused = false
    /// True while labels are up or scroll mode is on, and Jumpr takes the keys.
    var capturing = false
    var onHotkey: () -> Void = {}
    var onScrollHotkey: () -> Void = {}
    /// Returns true to swallow the key.
    var onKey: (Key) -> Bool = { _ in false }
    /// The system switched the tap off (it is switched back on before this is called).
    var onDisabled: () -> Void = {}

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    private static let escape: Int64 = 53
    private static let delete: Int64 = 51
    private static let commandControlOption = Modifiers.command | Modifiers.control | Modifiers.option

    init() {}

    /// Creates the tap on the main run loop. False when the system refuses (no permission).
    func start() -> Bool {
        if port != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let p = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: keyTapCallback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let s = CFMachPortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        port = p
        source = s
        return true
    }

    func stop() {
        guard let p = port else { return }
        CGEvent.tapEnable(tap: p, enable: false)
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        CFMachPortInvalidate(p)
        port = nil
        source = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let p = port { CGEvent.tapEnable(tap: p, enable: true) }
            onDisabled()
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, !suspended, !paused else { return Unmanaged.passUnretained(event) }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        if hotkey.matches(keyCode: code, flags: flags) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onHotkey() }
            return nil
        }
        if scrollHotkey.matches(keyCode: code, flags: flags) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onScrollHotkey() }
            return nil
        }
        guard capturing else { return Unmanaged.passUnretained(event) }
        return onKey(key(code: code, flags: flags, event: event)) ? nil : Unmanaged.passUnretained(event)
    }

    private func key(code: Int64, flags: UInt64, event: CGEvent) -> Key {
        var letter: Character? {
            guard let s = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased(), s.count == 1,
                  let c = s.first, Labels.alphabet.contains(c) else { return nil }
            return c
        }
        if flags & Self.commandControlOption != 0 {
            // A label letter keeps its modifiers: the session decides whether it is a click
            // of another kind or the shortcut it looks like (`Key.chord`).
            if let letter { return .chord(letter, held: flags & Modifiers.mask) }
            return .modified
        }
        if code == Self.escape { return .escape }
        if code == Self.delete { return .backspace }
        if let letter { return .character(letter, shift: flags & Modifiers.shift != 0) }
        return .other
    }
}

private let keyTapCallback: CGEventTapCallBack = { _, type, event, info in
    guard let info else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
}

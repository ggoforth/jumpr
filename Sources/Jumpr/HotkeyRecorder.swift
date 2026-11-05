import AppKit
import JumprCore
import SwiftUI

/// Click, then press the new combination. While recording, `onRecording(true)` has
/// suspended Jumpr's own key listener so the keys reach this window.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    var onRecording: (Bool) -> Void

    @State private var message: String?

    var body: some View {
        LabeledContent("Hotkey") {
            VStack(alignment: .trailing, spacing: 4) {
                RecorderControl(hotkey: $hotkey, message: $message, onRecording: onRecording)
                    .fixedSize()
                if let message {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct RecorderControl: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    @Binding var message: String?
    var onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.hotkey = hotkey
        b.onChange = { hotkey = $0 }
        b.onMessage = { message = $0 }
        b.onRecording = onRecording
        return b
    }

    func updateNSView(_ b: RecorderButton, context: Context) {
        if !b.isRecording, b.hotkey != hotkey { b.hotkey = hotkey }
    }
}

/// The AppKit side: a push button that captures the next key down through a local
/// event monitor. Recording always ends, with `onRecording(false)`, when the window
/// closes or stops being key, so the listener is never left suspended.
final class RecorderButton: NSButton {
    var hotkey: Hotkey = .default { didSet { refresh() } }
    var onChange: (Hotkey) -> Void = { _ in }
    var onMessage: (String?) -> Void = { _ in }
    var onRecording: (Bool) -> Void = { _ in }

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    var isRecording: Bool { monitor != nil }

    private static let escape: UInt16 = 53
    static let invalidMessage = "Use ⌘, ⌃ or ⌥ with a key"

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(clicked)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        stop()  // never leave the key listener suspended
    }

    @objc private func clicked() {
        isRecording ? stop() : start()
    }

    /// Records only while this window is key: otherwise the keys would not reach the
    /// monitor and the key listener would stay suspended for nothing.
    private func start() {
        guard !isRecording, window?.isKeyWindow == true else { return }
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return nil  // the recorder owns every key while recording
        }
        refresh()
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == Self.escape {
            stop()
            return
        }
        let mods = UInt64(event.modifierFlags.rawValue) & Modifiers.mask
        let candidate = Hotkey(keyCode: Int64(event.keyCode), modifiers: mods)
        guard candidate.isValid else {
            onMessage(Self.invalidMessage)
            return
        }
        hotkey = candidate
        stop()
        onChange(candidate)
    }

    /// Ends recording without changing the hotkey. Safe to call when not recording.
    func stop() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        onMessage(nil)
        refresh()
        onRecording(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let w = newWindow else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) {
                [weak self] _ in self?.stop()
            })
        }
    }

    private func refresh() {
        title = isRecording ? "Press new shortcut…" : hotkey.display(keyName: characterForKey)
        invalidateIntrinsicContentSize()
    }
}

/// The character `code` produces with no modifiers on the current keyboard layout,
/// or nil when it produces nothing printable. The event is only built, never posted.
func characterForKey(_ code: Int64) -> String? {
    guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true) else { return nil }
    cg.flags = []
    guard let s = NSEvent(cgEvent: cg)?.charactersIgnoringModifiers, !s.isEmpty else { return nil }
    let printable = s.unicodeScalars.allSatisfy { sc in
        !CharacterSet.controlCharacters.contains(sc) && !CharacterSet.whitespaces.contains(sc)
            && !(0xF700...0xF8FF).contains(sc.value)  // AppKit's function-key range
    }
    return printable ? s : nil
}

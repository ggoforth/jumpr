import AppKit
import JumprCore
import SwiftUI

/// One of the panel's shortcut rows: the hotkey as keycaps and "Change"; then press the new
/// combination. While recording, `onRecording(true)` has suspended Jumpr's own key
/// listener so the keys reach the panel.
struct HotkeyRecorder: View {
    var title = "Shortcut"
    @Binding var hotkey: Hotkey
    var accent: Color
    var onRecording: (Bool) -> Void

    @State private var recording = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(title)
                Spacer()
                if recording {
                    Text("Press the new shortcut")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent, lineWidth: 1.5))
                } else {
                    Keycaps(keys: hotkey.keycaps(keyName: characterForKey), height: 24)
                }
                RecorderControl(hotkey: $hotkey, recording: $recording, message: $message, onRecording: onRecording)
                    .fixedSize()
                    .padding(.leading, recording ? 3 : 6)
            }
            .frame(minHeight: 30)
            if recording {
                // Turns red after a press without ⌘, ⌃ or ⌥.
                Text(RecorderButton.invalidMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(message == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
    }
}

private struct RecorderControl: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    @Binding var recording: Bool
    @Binding var message: String?
    var onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onChange = { hotkey = $0 }
        b.onMessage = { message = $0 }
        b.onRecording = { on in
            recording = on
            onRecording(on)
        }
        return b
    }

    func updateNSView(_ b: RecorderButton, context: Context) {}
}

/// The AppKit side: "Change", which captures the next key down through a local event
/// monitor, and "Cancel" while it does. Recording always ends, with `onRecording(false)`,
/// when the window closes or stops being key, so the listener is never left suspended.
final class RecorderButton: NSButton {
    var onChange: (Hotkey) -> Void = { _ in }
    var onMessage: (String?) -> Void = { _ in }
    var onRecording: (Bool) -> Void = { _ in }

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    var isRecording: Bool { monitor != nil }

    private static let escape: UInt16 = 53
    static let invalidMessage = "It needs ⌘, ⌃ or ⌥ in it."

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        controlSize = .small
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
        title = isRecording ? "Cancel" : "Change"
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

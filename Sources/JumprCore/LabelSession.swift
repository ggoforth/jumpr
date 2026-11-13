public enum Key: Equatable {
    /// `shift`: held with Shift, which scroll mode reads (Shift G goes to the bottom) and
    /// labels read on the last letter (a right-click).
    case character(Character, shift: Bool = false)
    /// A label letter with ⌘, ⌃ or ⌥ held; `held` is every modifier down, Shift included.
    /// To the system it is a shortcut. While labels are up it can also pick the click.
    case chord(Character, held: UInt64)
    case backspace, escape, modified, other
}

/// The click a matched label gets, picked by what is held on the letter that completes it.
/// Before this Jumpr could only left-click: a file in Finder needs a double-click to open, a
/// link needs ⌘ to open in a new tab, and nothing reached a context menu.
public enum ClickKind: Equatable {
    case plain
    /// ⇧ on the last letter, as in Vimac and Homerow.
    case right
    /// ⌘ on the last letter: a click with ⌘ held, as in Homerow, Shortcat and Wooshy.
    case command
    /// ⌥ on the last letter. ⌃ was not used: on macOS a ⌃-click is already a right-click.
    case double
}

public enum Outcome: Equatable {
    case passThrough, swallow, narrowed(String), cancelled, matched(String, ClickKind = .plain)
}

/// What each key does while labels are on screen. The hotkey is not one of them: the key
/// listener takes it before this and cancels the session itself.
public struct LabelSession {
    public private(set) var typed: String = ""
    public var labels: Set<String> = []

    public init() {}

    public mutating func handle(_ key: Key) -> Outcome {
        switch key {
        case .modified:
            return .passThrough
        case .escape:
            return .cancelled
        case .other:
            return .swallow
        case .backspace:
            guard !typed.isEmpty else { return .swallow }
            typed.removeLast()
            return .narrowed(typed)
        case .chord(let c, let held):
            // Only ⌘ alone or ⌥ alone, and only on the letter that completes a label. Any
            // other chord stays the shortcut it is, so ⌘Q still quits with labels up.
            let candidate = typed + String(c).uppercased()
            guard labels.contains(candidate) else { return .passThrough }
            switch held & Modifiers.mask {
            case Modifiers.command: return .matched(candidate, .command)
            case Modifiers.option: return .matched(candidate, .double)
            default: return .passThrough
            }
        case .character(let c, let shift):
            let candidate = typed + String(c).uppercased()
            if labels.contains(candidate) { return .matched(candidate, shift ? .right : .plain) }
            if labels.contains(where: { $0.hasPrefix(candidate) }) {
                typed = candidate
                return .narrowed(candidate)
            }
            return .swallow
        }
    }
}

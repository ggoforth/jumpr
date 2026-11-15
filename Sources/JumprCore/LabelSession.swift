public enum Key: Equatable {
    /// `shift`: held with Shift, which scroll mode reads (Shift G goes to the bottom) and
    /// labels read on the last letter (the click set for ⇧, a right-click by default).
    case character(Character, shift: Bool = false)
    /// A label letter with ⌘, ⌃ or ⌥ held; `held` is every modifier down, Shift included.
    /// To the system it is a shortcut. While labels are up it can also pick the click.
    case chord(Character, held: UInt64)
    case backspace, escape, modified, other
}

/// The click a matched label gets, picked by what is held on the letter that completes it
/// (`ClickKeys`; the keys named here are the defaults).
/// Before this Jumpr could only left-click: a file in Finder needs a double-click to open, a
/// link needs ⌘ to open in a new tab, and nothing reached a context menu. The raw values
/// are the names in the stored setting and in the log.
public enum ClickKind: String, Equatable {
    case plain
    /// ⇧ on the last letter, as in Vimac and Homerow.
    case right
    /// ⌘ on the last letter: a click with ⌘ held, as in Homerow, Shortcat and Wooshy.
    case command
    /// ⌥ on the last letter. ⌃ was not used: on macOS a ⌃-click is already a right-click.
    case double
    /// A click with ⇧ held, which selects from the selected row to this one. It has ⌃, the
    /// one key the others left.
    case shift

    /// The clicks that take a key, in the order the panel lists them.
    public static let settable: [ClickKind] = [.right, .command, .double, .shift]
}

/// A key that can pick a click.
public enum ClickModifier: String, CaseIterable, Equatable {
    case shift, command, option, control

    public var flag: UInt64 {
        switch self {
        case .shift: Modifiers.shift
        case .command: Modifiers.command
        case .option: Modifiers.option
        case .control: Modifiers.control
        }
    }

    public var symbol: String {
        switch self {
        case .shift: "⇧"
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    public var name: String {
        switch self {
        case .shift: "Shift"
        case .command: "Command"
        case .option: "Option"
        case .control: "Control"
        }
    }
}

/// Which key, held on the letter that completes a label, gives which click. A key gives one
/// click at most, and a click may have no key at all.
public struct ClickKeys: Equatable {
    private var kinds: [ClickModifier: ClickKind]

    public static let `default` = ClickKeys(kinds: [.shift: .right, .command: .command,
                                                    .option: .double, .control: .shift])

    private init(kinds: [ClickModifier: ClickKind]) { self.kinds = kinds }

    /// Parses `stored`'s format, `"right=shift,command=command"`. Nil (never set) is the
    /// default. Otherwise the value is the whole truth: a click it leaves out has no key.
    /// An entry that names no settable click or no key is dropped, and so is a second
    /// claim on a click or a key.
    public init(stored: String?) {
        guard let stored else { self = .default; return }
        kinds = [:]
        for entry in stored.split(separator: ",") {
            let parts = entry.split(separator: "=")
            guard parts.count == 2,
                  let kind = ClickKind(rawValue: String(parts[0])), ClickKind.settable.contains(kind),
                  let modifier = ClickModifier(rawValue: String(parts[1])),
                  kinds[modifier] == nil, self.modifier(for: kind) == nil else { continue }
            kinds[modifier] = kind
        }
    }

    public var stored: String {
        ClickKind.settable.compactMap { kind in
            modifier(for: kind).map { "\(kind.rawValue)=\($0.rawValue)" }
        }.joined(separator: ",")
    }

    /// The click for `held`, the modifiers down with a letter: one of the four alone, or nil.
    public func kind(held: UInt64) -> ClickKind? {
        let down = held & Modifiers.mask
        return kinds.first { $0.key.flag == down }?.value
    }

    public func modifier(for kind: ClickKind) -> ClickModifier? {
        kinds.first { $0.value == kind }?.key
    }

    /// Gives `kind` the key `modifier`, or none. The click that had that key takes the one
    /// `kind` gives up, so choosing a key in use swaps the two.
    public mutating func set(_ modifier: ClickModifier?, for kind: ClickKind) {
        guard ClickKind.settable.contains(kind) else { return }
        let old = self.modifier(for: kind)
        guard modifier != old else { return }
        let displaced = modifier.flatMap { kinds[$0] }
        if let old { kinds[old] = displaced }
        if let modifier { kinds[modifier] = kind }
    }
}

public enum Outcome: Equatable {
    case passThrough, swallow, narrowed(String), cancelled, matched(String, ClickKind = .plain)
}

/// What each key does while labels are on screen. The hotkey is not one of them: the key
/// listener takes it before this and cancels the session itself.
public struct LabelSession {
    public private(set) var typed: String = ""
    public var labels: Set<String> = []
    private let clickKeys: ClickKeys

    public init(clickKeys: ClickKeys = .default) { self.clickKeys = clickKeys }

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
            // Only one key alone that has a click set for it, and only on the letter that
            // completes a label. Any other chord stays the shortcut it is, so ⌘Q still
            // quits with labels up.
            let candidate = typed + String(c).uppercased()
            guard labels.contains(candidate), let kind = clickKeys.kind(held: held) else { return .passThrough }
            return .matched(candidate, kind)
        case .character(let c, let shift):
            let candidate = typed + String(c).uppercased()
            if labels.contains(candidate) {
                return .matched(candidate, shift ? clickKeys.kind(held: Modifiers.shift) ?? .plain : .plain)
            }
            if labels.contains(where: { $0.hasPrefix(candidate) }) {
                typed = candidate
                return .narrowed(candidate)
            }
            return .swallow
        }
    }
}

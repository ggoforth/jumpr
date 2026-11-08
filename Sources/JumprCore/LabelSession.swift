public enum Key: Equatable {
    /// `shift`: held with Shift, which scroll mode reads (Shift G goes to the bottom).
    case character(Character, shift: Bool = false)
    case backspace, escape, modified, other
}

public enum Outcome: Equatable {
    case passThrough, swallow, narrowed(String), cancelled, matched(String)
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
        case .character(let c, _):
            let candidate = typed + String(c).uppercased()
            if labels.contains(candidate) { return .matched(candidate) }
            if labels.contains(where: { $0.hasPrefix(candidate) }) {
                typed = candidate
                return .narrowed(candidate)
            }
            return .swallow
        }
    }
}

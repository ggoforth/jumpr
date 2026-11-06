import CoreGraphics

public enum ScrollDirection: Equatable {
    case up, down
}

public enum ScrollAmount: Equatable {
    case line(ScrollDirection), half(ScrollDirection), top, bottom

    /// One line, in pixels.
    static let linePixels = 60
    /// Events in one burst: a line or half an area arrives as six small events (the shell
    /// spaces them 8 ms apart), which reads as a glide rather than a jump.
    static let burstEvents = 6
    /// The ends: one event far larger than any page.
    static let end: Int32 = 1_000_000

    /// The pixel amounts of the wheel events that make this scroll, in order. Positive
    /// scrolls up. A `burst` glides; without one the whole amount goes as one event, for a
    /// key repeat that arrives while the last burst is still going out.
    public func wheelSteps(areaHeight: CGFloat, burst: Bool = true) -> [Int32] {
        switch self {
        case .top: return [Self.end]
        case .bottom: return [-Self.end]
        case .line(let d): return Self.split(Self.linePixels, d, burst: burst)
        case .half(let d): return Self.split(Int((areaHeight / 2).rounded()), d, burst: burst)
        }
    }

    /// `total` in `burstEvents` events, the remainder spread over the first ones.
    private static func split(_ total: Int, _ d: ScrollDirection, burst: Bool) -> [Int32] {
        let sign: Int32 = d == .up ? 1 : -1
        guard burst else { return [sign * Int32(total)] }
        return (0..<burstEvents).map { i in sign * Int32(total / burstEvents + (i < total % burstEvents ? 1 : 0)) }
    }
}

public enum ScrollLetters {
    /// The keys that scroll, and F, which brings the letters back.
    public static let commands: Set<Character> = ["J", "K", "D", "U", "G", "F"]
    /// The label alphabet without the command keys, so a letter never means two things.
    public static let alphabet: [Character] = Labels.alphabet.filter { !commands.contains($0) }

    /// One letter per area unless the previous session found more areas than there are
    /// letters. Chosen before the scans finish, as label length is.
    public static func length(previousCount: Int?) -> Int {
        (previousCount ?? 0) <= alphabet.count ? 1 : 2
    }
}

/// What each key does while scroll mode is on. The shortcuts are not among them: the key
/// listener takes those first.
public struct ScrollSession {
    public enum Outcome: Equatable {
        /// Outline this area; the letters go.
        case outline(Area)
        case showLetters
        /// Show only the letters that start with this.
        case narrowed(String)
        /// Scroll this area; the letters go.
        case scroll(Area, by: ScrollAmount)
        case leave, swallow, passThrough
    }

    public private(set) var letters: [String: Area] = [:]
    public private(set) var lettersShown = true
    public private(set) var outlined: Area?
    /// Letters typed toward a two-letter area.
    public private(set) var typed = ""
    /// The person has picked an area or scrolled, so the starting outline stays put.
    private var acted = false
    private var pool: LabelPool

    public init(letterLength: Int) {
        pool = LabelPool(length: letterLength, alphabet: ScrollLetters.alphabet)
    }

    /// Gives `area` the next letter; nil once every letter is taken.
    public mutating func add(_ area: Area) -> String? {
        guard let letter = pool.next() else { return nil }
        letters[letter] = area
        return letter
    }

    /// Outlines where the session should start, as the scans come in, until the person acts.
    /// True if the outline changed.
    public mutating func suggest(_ area: Area?) -> Bool {
        guard !acted, let area, area != outlined else { return false }
        outlined = area
        return true
    }

    public mutating func handle(_ key: Key) -> Outcome {
        switch key {
        case .modified: return .passThrough
        case .escape: return .leave
        case .other: return .swallow
        case .backspace:
            guard !typed.isEmpty else { return .swallow }
            typed.removeLast()
            return .narrowed(typed)
        case .character(let c, let shift):
            let upper = Character(String(c).uppercased())
            if lettersShown && ScrollLetters.alphabet.contains(upper) { return pick(upper) }
            switch upper {
            case "J": return scroll(.line(.down))
            case "K": return scroll(.line(.up))
            case "D": return scroll(.half(.down))
            case "U": return scroll(.half(.up))
            case "G": return scroll(shift ? .bottom : .top)
            case "F":
                guard !lettersShown else { return .swallow }
                lettersShown = true
                typed = ""
                return .showLetters
            default: return .swallow
            }
        }
    }

    private mutating func pick(_ c: Character) -> Outcome {
        let candidate = typed + String(c)
        if let area = letters[candidate] {
            outlined = area
            acted = true
            lettersShown = false
            typed = ""
            return .outline(area)
        }
        guard letters.keys.contains(where: { $0.hasPrefix(candidate) }) else { return .swallow }
        typed = candidate
        return .narrowed(candidate)
    }

    private mutating func scroll(_ amount: ScrollAmount) -> Outcome {
        guard let area = outlined else { return .swallow }
        acted = true
        lettersShown = false
        typed = ""
        return .scroll(area, by: amount)
    }
}

/// Where a scroll session starts: the area scrolled last in the front window if an area
/// with its id is still there (as found now), else the smallest area holding the keyboard
/// focus, else none.
///
/// Holding the focus: the area contains the focused element's frame, with 6 pt to spare (a
/// focused page reports its whole frame, a few points off the area found for it). If none
/// does, the area showing most of it: a long text being edited is taller than the scroll
/// area that shows it.
public func startingArea(last: Area?, focusFrame: CGRect?, areas: [Area]) -> Area? {
    if let last, let found = areas.first(where: { $0.id == last.id }) { return found }
    guard let focus = focusFrame else { return nil }
    func size(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
    let holding = areas.filter { $0.rect.insetBy(dx: -6, dy: -6).contains(focus) }
    if let smallest = holding.min(by: { size($0.rect) < size($1.rect) }) { return smallest }
    let showing = areas.map { ($0, size($0.rect.intersection(focus))) }.filter { $0.1 > 0 }
    return showing.max { $0.1 < $1.1 || ($0.1 == $1.1 && size($0.0.rect) > size($1.0.rect)) }?.0
}

import CoreGraphics

public enum Labels {
    /// Home row first, then the rest of the letters.
    public static let alphabet: [Character] = Array("ASDFGHJKLQWERTYUIOPZXCVBNM")

    /// Fixed label length for an estimated element count, with 1.5x headroom.
    public static func length(forEstimate n: Int) -> Int {
        let needed = Int((1.5 * Double(n)).rounded(.up))
        if needed <= 26 { return 1 }
        if needed <= 676 { return 2 }
        return 3
    }

    /// Label rectangle in global top-left coordinates, clamped inside `screen`.
    ///
    /// The label must not hide what it points at. A target under four label widths gets
    /// its label hanging off its bottom-right corner, overlapping only a few points; at a
    /// screen edge the label flips to the other side of the target rather than sliding
    /// back over it. A larger target (a row, a wide button) keeps its label inside, at
    /// the right end: outside, it would straddle two stacked rows and belong to neither.
    public static func frame(length: Int, target: CGRect, screen: CGRect, fontSize: CGFloat, advance: CGFloat) -> CGRect {
        let w = ceil(CGFloat(length) * advance + fontSize * 0.6)
        let h = ceil(fontSize * 1.3)
        var x: CGFloat, y: CGFloat
        if target.width >= 4 * w {
            x = target.maxX - w - 2
            y = target.height >= 2 * h ? target.maxY - h - 2 : target.midY - h / 2
        } else {
            let ox = min(fontSize * 0.4, target.width / 4)
            let oy = min(fontSize * 0.4, target.height / 4)
            x = target.maxX - ox
            y = target.maxY - oy
            if x + w > screen.maxX { x = target.minX - w + ox }
            if y + h > screen.maxY { y = target.minY - h + oy }
        }
        let cx = max(screen.minX, min(x, screen.maxX - w))
        let cy = max(screen.minY, min(y, screen.maxY - h))
        return CGRect(x: cx, y: cy, width: w, height: h)
    }

    /// Index of the first screen containing `p`, or nil when it is on none.
    public static func screenIndex(for p: CGPoint, screens: [CGRect]) -> Int? {
        screens.firstIndex { $0.contains(p) }
    }
}

public struct LabelPool {
    public let length: Int
    private var index = 0
    private let total: Int

    public init(length: Int) {
        precondition(length > 0, "a label needs at least one letter")
        self.length = length
        var t = 1
        for _ in 0..<length { t *= Labels.alphabet.count }
        self.total = t
    }

    public var remaining: Int { total - index }

    /// Next unused label, or nil once every label of this length is handed out.
    public mutating func next() -> String? {
        guard index < total else { return nil }
        var digits: [Character] = []
        var n = index
        for _ in 0..<length {
            digits.append(Labels.alphabet[n % Labels.alphabet.count])
            n /= Labels.alphabet.count
        }
        index += 1
        return String(digits.reversed())
    }
}

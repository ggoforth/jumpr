import Foundation

/// One preset colour in the panel.
public struct Swatch: Equatable {
    public let name: String
    public let hex: String

    public init(_ name: String, _ hex: String) {
        self.name = name
        self.hex = hex
    }
}

/// The panel's colours, one palette for the label and for its letters: ten hues across, in
/// a light, a vivid and a deep row. The vivid row is the ten colours the presets offered
/// before the palette, so a colour chosen then still shows as selected.
public enum Palette {
    public static let rows: [[Swatch]] = [
        [
            Swatch("Light red", "FF9993"), Swatch("Light orange", "FFCA78"), Swatch("Light yellow", "FFE878"),
            Swatch("Light green", "8DE6A3"), Swatch("Light mint", "ABE7E5"), Swatch("Light sky", "AAE6FF"),
            Swatch("Light blue", "78BBFF"), Swatch("Light indigo", "A6A5F1"), Swatch("Light purple", "DCA4F8"),
            Swatch("Light pink", "FF91A7"),
        ],
        [
            Swatch("Red", "FF453A"), Swatch("Orange", "FF9F0A"), Swatch("Yellow", "FFD60A"),
            Swatch("Green", "30D158"), Swatch("Mint", "66D4CF"), Swatch("Sky", "64D2FF"),
            Swatch("Blue", "0A84FF"), Swatch("Indigo", "5E5CE6"), Swatch("Purple", "BF5AF2"),
            Swatch("Pink", "FF375F"),
        ],
        [
            Swatch("Deep red", "B8322A"), Swatch("Deep orange", "B87207"), Swatch("Deep yellow", "B89A07"),
            Swatch("Deep green", "23963F"), Swatch("Deep mint", "499995"), Swatch("Deep sky", "4897B8"),
            Swatch("Deep blue", "075FB8"), Swatch("Deep indigo", "4442A6"), Swatch("Deep purple", "8A41AE"),
            Swatch("Deep pink", "B82844"),
        ],
    ]
    public static let white = Swatch("White", "FFFFFF")
    /// A black label has been this dark grey since the presets, and black letters true black.
    /// Each keeps its value so a stored choice still shows as selected.
    public static let labelBlack = Swatch("Black", "1C1C1E")
    public static let letterBlack = Swatch("Black", "000000")
}

extension RGB {
    public static let black = RGB(r: 0, g: 0, b: 0)
    public static let white = RGB(r: 1, g: 1, b: 1)

    /// WCAG relative luminance of an sRGB colour, 0 (black) to 1 (white).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

/// Black or white letters, whichever reads better on `label`. The switch sits at 0.3,
/// not at the contrast midpoint (about 0.18), so mid colours such as the blue preset
/// get white letters.
public func readableLetters(on label: RGB) -> RGB {
    label.relativeLuminance > 0.3 ? .black : .white
}

/// The values stored under `Keys.labelTextMode`.
public enum LetterMode: String, CaseIterable {
    case auto, color
}

/// The letter colour setting, resolved from what is stored.
public enum Letters: Equatable {
    case auto
    case color(RGB)

    /// Without a stored mode, a stored letter colour is kept as it is: it was chosen in the
    /// colour picker that came before the mode, and an update must not change the labels.
    public init(storedMode: String?, storedTextColor: String?) {
        let stored = storedTextColor.flatMap(RGB.init(hex:))
        switch storedMode.flatMap(LetterMode.init(rawValue:)) {
        case .auto: self = .auto
        case .color, nil: self = stored.map { .color($0) } ?? .auto
        }
    }

    public func color(on label: RGB) -> RGB {
        switch self {
        case .auto: return readableLetters(on: label)
        case .color(let c): return c
        }
    }
}

/// What is typed into the panel's hex field.
public enum HexDraft {
    /// Only hex digits, at most six, uppercased: a pasted "#ff9f0a" becomes "FF9F0A".
    public static func clean(_ typed: String) -> String {
        String(typed.filter { $0.isASCII && $0.isHexDigit }.prefix(6)).uppercased()
    }

    /// The colour once the cleaned draft has all six digits; nil while it is shorter.
    public static func color(_ typed: String) -> RGB? {
        let draft = clean(typed)
        return draft.count == 6 ? RGB(hex: draft) : nil
    }
}

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

/// The panel's preset colours: for each picker, a first row and six more behind "More".
public enum Palette {
    public static let labelColors = [
        Swatch("Yellow", "FFD60A"), Swatch("Orange", "FF9F0A"), Swatch("Green", "30D158"),
        Swatch("Sky", "64D2FF"), Swatch("Blue", "0A84FF"), Swatch("Pink", "FF375F"),
    ]
    public static let moreLabelColors = [
        Swatch("Red", "FF453A"), Swatch("Purple", "BF5AF2"), Swatch("Indigo", "5E5CE6"),
        Swatch("Mint", "66D4CF"), Swatch("White", "FFFFFF"), Swatch("Black", "1C1C1E"),
    ]
    /// The first row's other five; Auto, which is not a colour, comes before them.
    public static let letterColors = [
        Swatch("Black", "000000"), Swatch("White", "FFFFFF"), Swatch("Yellow", "FFD60A"),
        Swatch("Blue", "0A84FF"), Swatch("Red", "FF453A"),
    ]
    public static let moreLetterColors = [
        Swatch("Orange", "FF9F0A"), Swatch("Green", "30D158"), Swatch("Sky", "64D2FF"),
        Swatch("Pink", "FF375F"), Swatch("Purple", "BF5AF2"), Swatch("Indigo", "5E5CE6"),
    ]
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

/// What is typed into an "Exact color" field.
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

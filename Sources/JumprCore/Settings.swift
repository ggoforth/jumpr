import Foundation

public enum Modifiers {
    public static let command: UInt64 = 0x100000
    public static let shift: UInt64 = 0x20000
    public static let control: UInt64 = 0x40000
    public static let option: UInt64 = 0x80000
    public static let mask: UInt64 = command | shift | control | option
}

public struct Hotkey: Equatable {
    public var keyCode: Int64
    public var modifiers: UInt64

    public static let `default` = Hotkey(keyCode: 49, modifiers: Modifiers.command | Modifiers.shift)

    public init(keyCode: Int64, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parses the `"<keyCode>:<modifiers>"` format produced by `stored`. Modifier bits
    /// other than command, shift, control and option are dropped.
    public init?(stored: String) {
        let parts = stored.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let code = Int64(parts[0]),
              let mods = UInt64(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: mods & Modifiers.mask)
    }

    public var stored: String { "\(keyCode):\(modifiers)" }

    /// A usable hotkey needs at least one of command, control or option.
    public var isValid: Bool {
        modifiers & (Modifiers.command | Modifiers.control | Modifiers.option) != 0
    }

    public func matches(keyCode: Int64, flags: UInt64) -> Bool {
        keyCode == self.keyCode && (flags & Modifiers.mask) == modifiers
    }

    /// Names for keys that produce no useful character. Nil for every other key.
    public static func keyName(_ code: Int64) -> String? {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }

    /// The combination as symbols, modifiers in the order ⌃⌥⇧⌘, e.g. `⇧⌘Space`.
    /// `keyName` returns the character a key produces without modifiers (from the
    /// keyboard layout); it is used only for keys `Hotkey.keyName` does not name.
    public func display(keyName lookup: (Int64) -> String?) -> String {
        var s = ""
        if modifiers & Modifiers.control != 0 { s += "⌃" }
        if modifiers & Modifiers.option != 0 { s += "⌥" }
        if modifiers & Modifiers.shift != 0 { s += "⇧" }
        if modifiers & Modifiers.command != 0 { s += "⌘" }
        let key = Hotkey.keyName(keyCode)
            ?? lookup(keyCode).map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Key \(keyCode)"
        return s + key
    }
}

public struct RGB: Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    /// Components in 0...1 (sRGB).
    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses exactly six hex digits, with or without a leading `#`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    public var hex: String {
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

public enum BatteryMode: String, CaseIterable {
    case full, frontApp, onDemand
}

/// Clamps to 10...32 pt; an unset (0 or less) or non-finite value falls back to the 15 pt default.
public func clampLabelSize(_ v: Double) -> Double {
    if !v.isFinite || v <= 0 { return 15 }
    return min(max(v, 10), 32)
}

public enum Keys {
    public static let labelSize = "labelSize"
    public static let labelColor = "labelColor"
    public static let labelTextColor = "labelTextColor"
    public static let hotkey = "hotkey"
    public static let batteryMode = "batteryMode"
    public static let showReadout = "showReadout"
    public static let paused = "paused"
    /// Set once the login item has been registered automatically or toggled by hand.
    public static let loginItemSetUp = "loginItemSetUp"
}

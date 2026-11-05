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

    /// Parses the `"<keyCode>:<modifiers>"` format produced by `stored`.
    public init?(stored: String) {
        let parts = stored.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let code = Int64(parts[0]),
              let mods = UInt64(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    public var stored: String { "\(keyCode):\(modifiers)" }

    /// A usable hotkey needs at least one of command, control or option.
    public var isValid: Bool {
        modifiers & (Modifiers.command | Modifiers.control | Modifiers.option) != 0
    }

    public func matches(keyCode: Int64, flags: UInt64) -> Bool {
        keyCode == self.keyCode && (flags & Modifiers.mask) == modifiers
    }
}

public struct RGB: Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    /// Parses six hex digits, with or without a leading `#`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
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

/// Clamps to 10...32 pt; an unset value (0 or less) falls back to the 15 pt default.
public func clampLabelSize(_ v: Double) -> Double {
    if v <= 0 { return 15 }
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
}

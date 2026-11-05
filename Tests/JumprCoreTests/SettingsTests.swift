import Testing
@testable import JumprCore

@Test func hexRoundTrip() {
    #expect(RGB(hex: "#FFD60A")?.hex == "FFD60A")
    #expect(RGB(hex: "ffd60a")?.hex == "FFD60A")
    #expect(RGB(hex: "zzz") == nil)
    #expect(RGB(hex: "FFF") == nil)
}
@Test func labelSizeClamps() {
    #expect(clampLabelSize(0) == 15)   // unset
    #expect(clampLabelSize(4) == 10)
    #expect(clampLabelSize(99) == 32)
    #expect(clampLabelSize(18) == 18)
}
@Test func defaultHotkeyIsCmdShiftSpace() {
    #expect(Hotkey.default == Hotkey(keyCode: 49, modifiers: Modifiers.command | Modifiers.shift))
}
@Test func hotkeyNeedsCmdCtrlOrOpt() {
    #expect(!Hotkey(keyCode: 38, modifiers: 0).isValid)
    #expect(!Hotkey(keyCode: 38, modifiers: Modifiers.shift).isValid)
    #expect(Hotkey(keyCode: 38, modifiers: Modifiers.control).isValid)
}
@Test func hotkeyMatchIgnoresNonModifierFlags() {
    let capsLock: UInt64 = 0x10000
    #expect(Hotkey.default.matches(keyCode: 49, flags: Modifiers.command | Modifiers.shift | capsLock))
    #expect(!Hotkey.default.matches(keyCode: 49, flags: Modifiers.command))
    #expect(!Hotkey.default.matches(keyCode: 38, flags: Modifiers.command | Modifiers.shift))
}
@Test func hotkeyStoredRoundTrip() {
    #expect(Hotkey(stored: Hotkey.default.stored) == .default)
    #expect(Hotkey(stored: "garbage") == nil)
}

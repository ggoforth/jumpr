import Testing
@testable import JumprCore

@Test func hexRoundTrip() {
    #expect(RGB(hex: "#FFD60A")?.hex == "FFD60A")
    #expect(RGB(hex: "ffd60a")?.hex == "FFD60A")
    #expect(RGB(hex: "zzz") == nil)
    #expect(RGB(hex: "FFF") == nil)
    #expect(RGB(r: 1, g: 214.0 / 255, b: 10.0 / 255).hex == "FFD60A")
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
@Test func defaultScrollShortcutIsCmdShiftJ() {
    #expect(Hotkey.defaultScroll == Hotkey(keyCode: 38, modifiers: Modifiers.command | Modifiers.shift))
    #expect(Hotkey.defaultScroll.isValid)
    #expect(Hotkey.defaultScroll != Hotkey.default)
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

// Display: modifiers ⌃⌥⇧⌘, then the key. The character lookup stands in for the keyboard layout.
private let noLookup: (Int64) -> String? = { _ in nil }
@Test func hotkeyDisplayDefault() {
    #expect(Hotkey.default.display(keyName: noLookup) == "⇧⌘Space")
}
@Test func hotkeyDisplayControlOptionLetterUsesLookupUppercased() {
    let h = Hotkey(keyCode: 38, modifiers: Modifiers.option | Modifiers.control)
    #expect(h.display(keyName: { $0 == 38 ? "j" : nil }) == "⌃⌥J")
}
@Test func hotkeyDisplayFunctionKeys() {
    #expect(Hotkey(keyCode: 122, modifiers: Modifiers.command).display(keyName: noLookup) == "⌘F1")
    #expect(Hotkey(keyCode: 111, modifiers: Modifiers.control).display(keyName: noLookup) == "⌃F12")
}
@Test func hotkeyDisplaySpecialKeysWinOverLookup() {
    let all = Modifiers.control | Modifiers.option | Modifiers.shift | Modifiers.command
    #expect(Hotkey(keyCode: 36, modifiers: all).display(keyName: { _ in "x" }) == "⌃⌥⇧⌘Return")
    #expect(Hotkey.keyName(48) == "Tab")
    #expect(Hotkey.keyName(51) == "Delete")
    #expect(Hotkey.keyName(53) == "Esc")
    #expect(Hotkey.keyName(123) == "←")
    #expect(Hotkey.keyName(124) == "→")
    #expect(Hotkey.keyName(125) == "↓")
    #expect(Hotkey.keyName(126) == "↑")
    #expect(Hotkey.keyName(38) == nil)
}
// The panel draws the hotkey as one keycap per key, in the same order as `display`.
@Test func hotkeyKeycapsAreOnePerKeyInDisplayOrder() {
    #expect(Hotkey.default.keycaps(keyName: noLookup) == ["⇧", "⌘", "Space"])
    let h = Hotkey(keyCode: 38, modifiers: Modifiers.option | Modifiers.control)
    #expect(h.keycaps(keyName: { $0 == 38 ? "j" : nil }) == ["⌃", "⌥", "J"])
}
@Test func hotkeyDisplayUnknownKeyFallsBackToCode() {
    #expect(Hotkey(keyCode: 200, modifiers: Modifiers.command).display(keyName: noLookup) == "⌘Key 200")
}

@Test func hexRejectsAnythingButSixHexDigits() {
    #expect(RGB(hex: "+FFD60") == nil)     // UInt32(radix:) alone would take the sign
    #expect(RGB(hex: "-FFD60") == nil)
    #expect(RGB(hex: "##FFD60") == nil)
    #expect(RGB(hex: "FFD60G") == nil)
    #expect(RGB(hex: "#ffd60a") == RGB(hex: "FFD60A"))
}

@Test func storedHotkeyKeepsOnlyKnownModifiers() {
    let capsLockAndNumericPad: UInt64 = 0x10000 | 0x200000
    let h = Hotkey(stored: "49:\(Modifiers.command | Modifiers.shift | capsLockAndNumericPad)")
    #expect(h == Hotkey.default)
}

@Test func nonFiniteLabelSizeFallsBackToDefault() {
    #expect(clampLabelSize(.nan) == 15)
    #expect(clampLabelSize(.infinity) == 15)
    #expect(clampLabelSize(-.infinity) == 15)
}

// Hidden settings are set by hand with `defaults write`, so their names must not drift.
@Test func handSetKeysKeepTheirNames() {
    #expect(Keys.showReadout == "showReadout")
    #expect(Keys.showAdvancedSettings == "showAdvancedSettings")
}

// The key held on a label's last letter for each kind of click, set in the panel.

@Test func theDefaultClickKeysAreShiftCommandOptionControl() {
    let keys = ClickKeys.default
    #expect(keys.modifier(for: .right) == .shift)
    #expect(keys.modifier(for: .command) == .command)
    #expect(keys.modifier(for: .double) == .option)
    #expect(keys.modifier(for: .shift) == .control)
    #expect(ClickKeys(stored: nil) == .default)
}

@Test func clickKeysRoundTripThroughTheirStoredForm() {
    var keys = ClickKeys.default
    keys.set(.control, for: .double)
    keys.set(nil, for: .command)
    #expect(ClickKeys(stored: keys.stored) == keys)
    #expect(ClickKeys(stored: ClickKeys.default.stored) == .default)
}

// A stored value is the whole truth: a click it does not name has no key, so "None" in the
// panel survives a relaunch.
@Test func aClickTheStoredValueLeavesOutHasNoKey() {
    let keys = ClickKeys(stored: "right=control,shift=shift")
    #expect(keys.modifier(for: .right) == .control)
    #expect(keys.modifier(for: .shift) == .shift)
    #expect(keys.modifier(for: .command) == nil)
    #expect(keys.modifier(for: .double) == nil)
    #expect(ClickKeys(stored: "").kind(held: Modifiers.shift) == nil)
}

// `defaults write` can store anything. Nonsense is dropped, and a key named twice goes to
// the click that named it first, so one key never means two clicks.
@Test func aBadStoredClickKeyIsDroppedAndAKeyIsNeverSharedByTwoClicks() {
    let keys = ClickKeys(stored: "right=shift,double=shift,plain=option,command=hyper,nonsense")
    #expect(keys.modifier(for: .right) == .shift)
    #expect(keys.modifier(for: .double) == nil)
    #expect(keys.modifier(for: .command) == nil)
    #expect(keys.kind(held: Modifiers.option) == nil)
}

// Choosing a key another click already has swaps the two rather than leaving one without.
@Test func settingAKeyAnotherClickHasSwapsTheTwo() {
    var keys = ClickKeys.default
    keys.set(.shift, for: .shift)
    #expect(keys.modifier(for: .shift) == .shift)
    #expect(keys.modifier(for: .right) == .control)
    keys.set(nil, for: .right)
    keys.set(.shift, for: .right)  // right had no key to give back
    #expect(keys.modifier(for: .right) == .shift)
    #expect(keys.modifier(for: .shift) == nil)
}

@Test func onlyOneModifierHeldAlonePicksAClick() {
    let keys = ClickKeys.default
    #expect(keys.kind(held: Modifiers.option) == .double)
    #expect(keys.kind(held: Modifiers.option | Modifiers.command) == nil)
    #expect(keys.kind(held: 0) == nil)
    #expect(keys.kind(held: Modifiers.option | 0x100) == .double)  // flags that are not modifiers
}

// The panel's menu for a click names its key in full, as "⌃ Control". As bare symbols, five
// to a row and four rows deep, the keys were the clutter that split the panel into tabs.
@Test func eachClickKeyHasANameToGoWithItsSymbol() {
    #expect(ClickModifier.allCases.map(\.name) == ["Shift", "Command", "Option", "Control"])
}

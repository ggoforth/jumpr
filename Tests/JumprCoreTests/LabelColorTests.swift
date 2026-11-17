import Testing
@testable import JumprCore

// One palette serves the label and its letters: ten hues across, each in a light, a vivid
// and a deep shade. Before it each had its own row of presets, a second row behind "More"
// and its own exact-colour field, which was most of the panel's height.
@Test func thePaletteHasTenHuesInThreeShades() {
    #expect(Palette.rows.count == 3)
    #expect(Palette.rows.allSatisfy { $0.count == 10 })
    #expect(Palette.rows[1].map(\.name)
        == ["Red", "Orange", "Yellow", "Green", "Mint", "Sky", "Blue", "Indigo", "Purple", "Pink"])
    #expect(Palette.rows[0].map(\.name) == Palette.rows[1].map { "Light \($0.name.lowercased())" })
    #expect(Palette.rows[2].map(\.name) == Palette.rows[1].map { "Deep \($0.name.lowercased())" })
}

// A colour picked from the presets before the palette (yellow, the default, among them)
// must still show as selected, so the vivid row is exactly those ten.
@Test func theVividRowKeepsEveryColorThePresetsOffered() {
    #expect(Palette.rows[1].map(\.hex)
        == ["FF453A", "FF9F0A", "FFD60A", "30D158", "66D4CF", "64D2FF", "0A84FF", "5E5CE6", "BF5AF2", "FF375F"])
}

// White and black sit beside the palette. A black label was always the dark grey 1C1C1E,
// and black letters true black; both stay, so neither stored choice loses its ring.
@Test func blackIsDarkGreyForALabelAndTrueBlackForLetters() {
    #expect(Palette.white.hex == "FFFFFF")
    #expect(Palette.labelBlack.hex == "1C1C1E")
    #expect(Palette.letterBlack.hex == "000000")
}

// Every colour must parse, or picking it would store a colour the labels cannot show; and
// each is offered once, or two swatches would show the ring together.
@Test func everyPaletteColorIsAValidHexColorOfferedOnce() {
    let all = Palette.rows.flatMap { $0 } + [Palette.white, Palette.labelBlack, Palette.letterBlack]
    for s in all {
        #expect(RGB(hex: s.hex)?.hex == s.hex)
    }
    #expect(Set(all.map(\.hex)).count == all.count)
}

// Auto letters: black on the default yellow, white on blue, readable on both ends.
@Test func autoLettersAreBlackOnLightColorsAndWhiteOnDarkOnes() {
    #expect(readableLetters(on: RGB(hex: "FFD60A")!) == .black)
    #expect(readableLetters(on: RGB(hex: "0A84FF")!) == .white)
    #expect(readableLetters(on: RGB(hex: "FFFFFF")!) == .black)
    #expect(readableLetters(on: RGB(hex: "1C1C1E")!) == .white)
}

// The switch is at a relative luminance of 0.3: grey 949494 is just under it, 959595 just over.
@Test func autoLettersSwitchToBlackAboveALuminanceOfPointThree() {
    #expect(RGB(hex: "949494")!.relativeLuminance < 0.3)
    #expect(RGB(hex: "959595")!.relativeLuminance > 0.3)
    #expect(readableLetters(on: RGB(hex: "949494")!) == .white)
    #expect(readableLetters(on: RGB(hex: "959595")!) == .black)
}

// Picking Auto stores mode "auto": the letters follow the label colour from then on.
@Test func autoModeIgnoresAnyStoredLetterColor() {
    let letters = Letters(storedMode: "auto", storedTextColor: "FF0000")
    #expect(letters == .auto)
    #expect(letters.color(on: RGB(hex: "0A84FF")!) == .white)
}

// Picking a swatch or an exact colour stores mode "color" and the hex.
@Test func colorModeUsesTheStoredLetterColor() {
    let letters = Letters(storedMode: "color", storedTextColor: "FF453A")
    #expect(letters == .color(RGB(hex: "FF453A")!))
    #expect(letters.color(on: RGB(hex: "FFD60A")!) == RGB(hex: "FF453A")!)
}

// A colour mode whose hex was removed or garbled by hand still draws readable letters.
@Test func colorModeWithoutAReadableColorFallsBackToAuto() {
    #expect(Letters(storedMode: "color", storedTextColor: nil) == .auto)
    #expect(Letters(storedMode: "color", storedTextColor: "nonsense") == .auto)
}

// A fresh install has stored nothing, and gets black on yellow as it always has.
@Test func anUntouchedInstallKeepsBlackLettersOnYellow() {
    let letters = Letters(storedMode: nil, storedTextColor: nil)
    #expect(letters == .auto)
    #expect(letters.color(on: RGB(hex: "FFD60A")!) == .black)
}

// An install from before the mode existed stored the old colour picker's letter colour.
// Whatever it is, it is kept exactly, so nothing changes on screen after the update.
@Test func anOlderLetterColorIsKeptExactlyAfterTheUpdate() {
    #expect(Letters(storedMode: nil, storedTextColor: "000000") == .color(.black))
    #expect(Letters(storedMode: nil, storedTextColor: "FFFFFF").color(on: RGB(hex: "FFFFFF")!) == .white)
    #expect(Letters(storedMode: nil, storedTextColor: "ff0000") == .color(RGB(hex: "FF0000")!))
}

// A mode that is not one of the two (set by hand) counts as not stored.
@Test func anUnknownLettersModeCountsAsNotStored() {
    #expect(Letters(storedMode: "pink", storedTextColor: "FF0000") == .color(RGB(hex: "FF0000")!))
    #expect(Letters(storedMode: "pink", storedTextColor: nil) == .auto)
}

// The stored mode is written by the panel and may be set by hand, so its values must not drift.
@Test func lettersModesKeepTheirStoredNames() {
    #expect(Keys.labelTextMode == "labelTextMode")
    #expect(Keys.labelTextColor == "labelTextColor")
    #expect(LetterMode.allCases.map(\.rawValue) == ["auto", "color"])
}

// The "Exact color" field: a pasted "#ff9f0a" or a typo must not reach the stored colour.
@Test func aHexDraftKeepsOnlySixUppercaseHexDigits() {
    #expect(HexDraft.clean("#ff9f0a") == "FF9F0A")
    #expect(HexDraft.clean("12 34-zz") == "1234")
    #expect(HexDraft.clean("ABCDEF0123") == "ABCDEF")
    #expect(HexDraft.clean("") == "")
}

@Test func aHexDraftGivesAColorOnlyAtSixDigits() {
    #expect(HexDraft.color("FF9F0") == nil)
    #expect(HexDraft.color("") == nil)
    #expect(HexDraft.color("#ff9f0a") == RGB(hex: "FF9F0A"))
    #expect(HexDraft.color("FF9F0A99") == RGB(hex: "FF9F0A"))  // capped, as the field shows it
}

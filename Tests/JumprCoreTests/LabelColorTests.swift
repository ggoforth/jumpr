import Testing
@testable import JumprCore

// Label color: two rows of six, the second behind "More".
@Test func theLabelColorsComeInTwoRowsOfSix() {
    #expect(Palette.labelColors.map(\.name) == ["Yellow", "Orange", "Green", "Sky", "Blue", "Pink"])
    #expect(Palette.labelColors.map(\.hex) == ["FFD60A", "FF9F0A", "30D158", "64D2FF", "0A84FF", "FF375F"])
    #expect(Palette.moreLabelColors.map(\.name) == ["Red", "Purple", "Indigo", "Mint", "White", "Black"])
    #expect(Palette.moreLabelColors.map(\.hex) == ["FF453A", "BF5AF2", "5E5CE6", "66D4CF", "FFFFFF", "1C1C1E"])
}

// Letter color: Auto leads the first row (it is not a colour, so it is not in the data),
// then five colours; six more behind "More". Some eyes read a coloured letter better.
@Test func theLetterColorsFollowAutoInTwoRows() {
    #expect(Palette.letterColors.map(\.name) == ["Black", "White", "Yellow", "Blue", "Red"])
    #expect(Palette.letterColors.map(\.hex) == ["000000", "FFFFFF", "FFD60A", "0A84FF", "FF453A"])
    #expect(Palette.moreLetterColors.map(\.name) == ["Orange", "Green", "Sky", "Pink", "Purple", "Indigo"])
    #expect(Palette.moreLetterColors.map(\.hex) == ["FF9F0A", "30D158", "64D2FF", "FF375F", "BF5AF2", "5E5CE6"])
}

// Every preset must parse, or picking it would store a colour the labels cannot show.
@Test func everyPresetColorIsAValidHexColor() {
    for s in Palette.labelColors + Palette.moreLabelColors + Palette.letterColors + Palette.moreLetterColors {
        #expect(RGB(hex: s.hex)?.hex == s.hex)
    }
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

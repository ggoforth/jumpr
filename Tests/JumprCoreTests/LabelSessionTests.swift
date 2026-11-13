import Testing
@testable import JumprCore

@Test func typingNarrowsThenMatches() {
    var s = LabelSession(); s.labels = ["AA", "AS", "SD"]
    #expect(s.handle(.character("a")) == .narrowed("A"))
    #expect(s.handle(.character("S")) == .matched("AS"))
}

@Test func unknownLettersAreSwallowed() {
    var s = LabelSession(); s.labels = ["AA"]
    #expect(s.handle(.character("Q")) == .swallow)
    #expect(s.typed == "")
    #expect(s.handle(.other) == .swallow)
}

@Test func backspaceEscapeHotkeyModified() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    #expect(s.handle(.backspace) == .swallow)
    _ = s.handle(.character("A"))
    #expect(s.handle(.backspace) == .narrowed(""))
    #expect(s.handle(.modified) == .passThrough)
    #expect(s.handle(.escape) == .cancelled)
}

@Test func labelsAddedMidSessionCanMatch() {
    var s = LabelSession(); s.labels = ["AA"]
    #expect(s.handle(.character("S")) == .swallow)
    s.labels.insert("SD")
    #expect(s.handle(.character("S")) == .narrowed("S"))
    #expect(s.handle(.character("D")) == .matched("SD"))
}

@Test func backspaceFromTwoLettersNarrowsToOne() {
    var s = LabelSession(); s.labels = ["AAA", "ASD"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S")) == .narrowed("AS"))
    #expect(s.handle(.backspace) == .narrowed("A"))
    #expect(s.typed == "A")
}

// JUM-104: Jumpr could only left-click. A file in Finder needs a double-click to open, a
// link needs ⌘ to open in a new tab, and nothing reached a context menu. The modifier held
// on the letter that completes a label picks the click.

@Test func shiftOnTheLastLetterRightClicks() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S", shift: true)) == .matched("AS", .right))
}

@Test func commandOnTheLastLetterCommandClicks() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.command)) == .matched("AS", .command))
}

@Test func optionOnTheLastLetterDoubleClicks() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.option)) == .matched("AS", .double))
}

@Test func aPlainLastLetterStillClicksPlainly() {
    var s = LabelSession(); s.labels = ["AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S")) == .matched("AS", .plain))
}

@Test func shiftOnAnEarlierLetterOnlyNarrows() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    #expect(s.handle(.character("A", shift: true)) == .narrowed("A"))
    #expect(s.handle(.character("S")) == .matched("AS", .plain))
}

// ⌘Q with labels up must still quit, and ⌘A still select all: only the letter that
// completes a label is taken from the app.
@Test func aShortcutThatCompletesNoLabelStillPassesThrough() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    #expect(s.handle(.chord("A", held: Modifiers.command)) == .passThrough)
    #expect(s.typed == "")
    #expect(s.handle(.chord("Q", held: Modifiers.option)) == .passThrough)
}

// ⌘⇧S, ⌘⌥S and ⌃S are shortcuts and nothing else, even on a letter that completes a label.
@Test func twoModifiersOrControlOnTheLastLetterPassThrough() {
    var s = LabelSession(); s.labels = ["AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.command | Modifiers.shift)) == .passThrough)
    #expect(s.handle(.chord("S", held: Modifiers.command | Modifiers.option)) == .passThrough)
    #expect(s.handle(.chord("S", held: Modifiers.control)) == .passThrough)
    #expect(s.typed == "A")
}

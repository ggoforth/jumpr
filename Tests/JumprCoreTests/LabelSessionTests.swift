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

// ⌘⇧S and ⌘⌥S are shortcuts and nothing else, even on a letter that completes a label.
@Test func twoModifiersOnTheLastLetterPassThrough() {
    var s = LabelSession(); s.labels = ["AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.command | Modifiers.shift)) == .passThrough)
    #expect(s.handle(.chord("S", held: Modifiers.command | Modifiers.option)) == .passThrough)
    #expect(s.handle(.chord("S", held: Modifiers.control | Modifiers.shift)) == .passThrough)
    #expect(s.typed == "A")
}

// Greg, 2026-11-13, in Watchflows' flow list: a click selects the first row and a double-click
// opens it, but nothing selected the rows down to a lower one, which a ⇧-click does. ⇧ was
// taken by the right-click, so the ⇧-click got the one key left.
@Test func controlOnTheLastLetterShiftClicks() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.control)) == .matched("AS", .shift))
}

// The same day: "can we add these to our keyboard shortcuts in the menu bar app, so we can
// set them?" The key for each click is a setting, and the session follows it.
@Test func theKeySetForAClickPicksThatClick() {
    var keys = ClickKeys.default
    keys.set(.shift, for: .shift)  // ⇧ is the ⇧-click; the right-click takes ⌃ in exchange
    var s = LabelSession(clickKeys: keys); s.labels = ["AS", "AD"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S", shift: true)) == .matched("AS", .shift))
    #expect(s.handle(.chord("D", held: Modifiers.control)) == .matched("AD", .right))
}

@Test func aClickWithNoKeyLeavesItsOldKeyAShortcut() {
    var keys = ClickKeys.default
    keys.set(nil, for: .command)
    var s = LabelSession(clickKeys: keys); s.labels = ["AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.command)) == .passThrough)
    #expect(s.typed == "A")
}

// ⇧ with no click set for it is a capital letter and nothing more, as on an earlier letter.
@Test func shiftWithNoClickSetForItClicksPlainly() {
    var keys = ClickKeys.default
    keys.set(nil, for: .right)
    var s = LabelSession(clickKeys: keys); s.labels = ["AS"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S", shift: true)) == .matched("AS", .plain))
}

// A run of presses (a site, Play now, Start game) should take one invocation.
@Test func spaceSwitchesPersistentModeOnAndOffAgain() {
    var s = LabelSession(); s.labels = ["AA"]
    #expect(s.handle(.space) == .persistent(true))
    #expect(s.persistent)
    #expect(s.handle(.space) == .persistent(false))
    #expect(!s.persistent)
}

// Tab is swallowed today; outside persistent mode it must stay that way.
@Test func tabAsksForARefreshOnlyInPersistentMode() {
    var s = LabelSession(); s.labels = ["AA"]
    #expect(s.handle(.tab) == .swallow)
    _ = s.handle(.space)
    #expect(s.handle(.tab) == .refresh)
}

// The session lives on after the press, so the letters of the last label must not narrow the next.
@Test func aMatchInPersistentModeClearsWhatWasTyped() {
    var s = LabelSession(persistent: true); s.labels = ["AS", "AD"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S")) == .matched("AS"))
    #expect(s.typed == "")
}

// A page reloads after "A" was typed and every label starting with A is removed:
// without this every key is swallowed until Backspace.
@Test func typedLettersAreClearedWhenNoLabelStartsWithThem() {
    var s = LabelSession(persistent: true); s.labels = ["AS", "DF"]
    _ = s.handle(.character("A"))
    let whileLabelsMatch = s.clearTypedIfNothingMatches()
    #expect(!whileLabelsMatch)   // "AS" still starts with it
    s.labels.remove("AS")
    let afterTheyWereRemoved = s.clearTypedIfNothingMatches()
    #expect(afterTheyWereRemoved)
    #expect(s.typed == "")
    let withNothingTyped = s.clearTypedIfNothingMatches()
    #expect(!withNothingTyped)
}

// ⌘ on the last letter in persistent mode opens a link in a new tab and the run goes on:
// "AS" left typed would make the next "D" try "ASD" and swallow it.
@Test func aChordMatchInPersistentModeClearsWhatWasTyped() {
    var s = LabelSession(persistent: true); s.labels = ["AS", "AD"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.chord("S", held: Modifiers.command)) == .matched("AS", .command))
    #expect(s.typed == "")
}

// Review of persistent mode: holding the S of "AS" past the repeat delay sent S again and
// again. After the match the first repeat narrowed to "S", the next matched "SS" and pressed
// it, and so on until the key came up. A repeated letter is never typing.
@Test func aHeldLetterAfterAMatchInPersistentModeNeitherNarrowsNorMatches() {
    var s = LabelSession(persistent: true); s.labels = ["AS", "SS", "SD"]
    _ = s.handle(.character("A"))
    #expect(s.handle(.character("S")) == .matched("AS"))
    #expect(s.handle(.character("S"), isRepeat: true) == .swallow)
    #expect(s.typed == "")
    #expect(s.handle(.character("S"), isRepeat: true) == .swallow)
    #expect(s.typed == "")
}

// The one-shot form on main: holding the A of "AA" a moment too long pressed "AA".
@Test func aHeldFirstLetterOutsidePersistentModeDoesNotTypeTheSecondLetterOfALabel() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    #expect(s.handle(.character("A")) == .narrowed("A"))
    #expect(s.handle(.character("A"), isRepeat: true) == .swallow)
    #expect(s.typed == "A")
}

// ⌘S held on a one-letter label: the repeat would ⌘-click "S" again, once per repeat.
@Test func aHeldChordThatWouldCompleteALabelDoesNotMatch() {
    var s = LabelSession(persistent: true); s.labels = ["S", "D"]
    #expect(s.handle(.chord("S", held: Modifiers.command)) == .matched("S", .command))
    #expect(s.handle(.chord("S", held: Modifiers.command), isRepeat: true) == .swallow)
    #expect(s.typed == "")
}

// A held ⌘Z keeps undoing in the app, as it does with no labels up.
@Test func aHeldChordThatIsAShortcutStillPassesThrough() {
    var s = LabelSession(persistent: true); s.labels = ["AS"]
    #expect(s.handle(.chord("Z", held: Modifiers.command), isRepeat: true) == .passThrough)
}

// Holding Backspace still takes letters off one at a time, as it does today.
@Test func aHeldBackspaceStillNarrows() {
    var s = LabelSession(); s.labels = ["AAA", "ASD"]
    _ = s.handle(.character("A"))
    _ = s.handle(.character("S"))
    #expect(s.handle(.backspace, isRepeat: true) == .narrowed("A"))
}

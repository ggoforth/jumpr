import Testing
import CoreGraphics
@testable import JumprCore

private func area(_ id: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, window: WindowID = 1) -> Area {
    Area(id: ElementID(id), rect: CGRect(x: x, y: y, width: w, height: h), pid: 10, window: window)
}
private let sidebar = area(1, 0, 0, 200, 600), list = area(2, 200, 0, 600, 600), page = area(3, 900, 0, 800, 900)

/// A session with the three areas lettered in order: A, S, H.
private func session(outlined: Area? = nil) -> ScrollSession {
    var s = ScrollSession(letterLength: 1)
    for a in [sidebar, list, page] { _ = s.add(a) }
    if let outlined { _ = s.suggest(outlined) }
    return s
}

// Every area gets one letter, from the label alphabet without the keys that scroll.
@Test func areasAreLetteredWithoutTheScrollKeys() {
    #expect(ScrollLetters.alphabet == Array("ASHLQWERTYIOPZXCVBNM"))
    var s = ScrollSession(letterLength: 1)
    let given = [sidebar, list, page].map { s.add($0) }
    #expect(given == ["A", "S", "H"])
    #expect(s.letters["S"] == list)
    #expect(s.lettersShown)
}
@Test func areasBeyondTheLettersGetNone() {
    var s = ScrollSession(letterLength: 1)
    let given = (0..<21).map { s.add(area($0, 0, 0, 100, 100)) }
    #expect(given.prefix(20).allSatisfy { $0 != nil })
    #expect(given[20] == nil)
}
@Test func twoLettersOnlyWhenTheLastSessionHadMoreAreasThanLetters() {
    #expect(ScrollLetters.length(previousCount: nil) == 1)
    #expect(ScrollLetters.length(previousCount: 20) == 1)
    #expect(ScrollLetters.length(previousCount: 21) == 2)
}

// J scrolls the outlined area at once; the letters go as soon as scrolling starts.
@Test func jScrollsTheOutlinedAreaAndHidesTheLetters() {
    var s = session(outlined: list)
    #expect(s.handle(.character("J")) == .scroll(list, by: .line(.down)))
    #expect(!s.lettersShown)
}
@Test func eachScrollKeyScrollsByItsAmount() {
    var s = session(outlined: list)
    #expect(s.handle(.character("j")) == .scroll(list, by: .line(.down)))
    #expect(s.handle(.character("k")) == .scroll(list, by: .line(.up)))
    #expect(s.handle(.character("d")) == .scroll(list, by: .half(.down)))
    #expect(s.handle(.character("u")) == .scroll(list, by: .half(.up)))
    #expect(s.handle(.character("g")) == .scroll(list, by: .top))
    #expect(s.handle(.character("G", shift: true)) == .scroll(list, by: .bottom))
}
@Test func withNothingOutlinedTheScrollKeysDoNothing() {
    var s = session()
    #expect(s.handle(.character("J")) == .swallow)
    #expect(s.handle(.character("G", shift: true)) == .swallow)
    #expect(s.lettersShown)
}
// Typing a letter outlines a different area first, and the letters go.
@Test func aLetterOutlinesItsAreaAndHidesTheLetters() {
    var s = session(outlined: list)
    #expect(s.handle(.character("h")) == .outline(page))
    #expect(s.outlined == page)
    #expect(!s.lettersShown)
    #expect(s.handle(.character("J")) == .scroll(page, by: .line(.down)))
}
@Test func lettersPickNothingWhileHidden() {
    var s = session(outlined: list)
    _ = s.handle(.character("J"))
    #expect(s.handle(.character("A")) == .swallow)
    #expect(s.outlined == list)
}
@Test func fBringsTheLettersBack() {
    var s = session(outlined: list)
    _ = s.handle(.character("J"))
    #expect(s.handle(.character("F")) == .showLetters)
    #expect(s.lettersShown)
    #expect(s.handle(.character("F")) == .swallow)   // already showing
    #expect(s.handle(.character("A")) == .outline(sidebar))
}
@Test func escLeavesModifiedKeysPassOtherKeysAreSwallowed() {
    var s = session(outlined: list)
    #expect(s.handle(.escape) == .leave)
    #expect(s.handle(.modified) == .passThrough)
    #expect(s.handle(.other) == .swallow)
    #expect(s.handle(.backspace) == .swallow)
    #expect(s.handle(.character("Q")) == .swallow)   // a letter no area has
}
// With more areas than letters, each has two: the first letter narrows, Backspace undoes it.
@Test func twoLetterAreasNarrowThenOutline() {
    var s = ScrollSession(letterLength: 2)
    let given = [sidebar, list].map { s.add($0) }
    #expect(given == ["AA", "AS"])
    #expect(s.handle(.character("a")) == .narrowed("A"))
    #expect(s.handle(.backspace) == .narrowed(""))
    _ = s.handle(.character("a"))
    #expect(s.handle(.character("s")) == .outline(list))
    #expect(s.typed == "")
}

// The starting outline follows the scans in until the person acts.
@Test func theStartingOutlineMovesOnlyUntilThePersonActs() {
    var s = session()
    #expect(s.suggest(sidebar) == true)
    #expect(s.suggest(sidebar) == false)   // no change
    #expect(s.suggest(list) == true)
    _ = s.handle(.character("J"))
    #expect(s.suggest(page) == false)
    #expect(s.outlined == list)
}
@Test func aChosenAreaIsNotMovedBySuggestions() {
    var s = session()
    _ = s.handle(.character("H"))
    #expect(s.suggest(list) == false)
    #expect(s.outlined == page)
}

// The area scrolled last in the window, if it is still there, else the one holding the
// keyboard focus, else none.
@Test func theLastScrolledAreaStartsIfItIsStillThere() {
    let moved = area(2, 200, 40, 600, 560)   // the same element, now a little lower
    #expect(startingArea(last: list, focusFrame: CGRect(x: 10, y: 10, width: 20, height: 20),
                         areas: [sidebar, moved]) == moved)
}
@Test func withTheLastAreaGoneTheFocusDecides() {
    #expect(startingArea(last: page, focusFrame: CGRect(x: 10, y: 10, width: 20, height: 20),
                         areas: [sidebar, list]) == sidebar)
}
@Test func theFocusPicksTheSmallestAreaHoldingIt() {
    let region = area(4, 300, 100, 300, 300)   // inside the list
    #expect(startingArea(last: nil, focusFrame: CGRect(x: 320, y: 120, width: 40, height: 20),
                         areas: [list, region, sidebar]) == region)
}
// A focused page reports its whole frame, a few points off the area found for it.
@Test func aFocusedPageStartsInItsOwnArea() {
    let region = area(4, 1000, 100, 300, 300)
    #expect(startingArea(last: nil, focusFrame: CGRect(x: 897, y: -3, width: 806, height: 906),
                         areas: [page, region]) == page)
}
// A long text being edited is taller than the scroll area that shows it.
@Test func aFocusTallerThanEveryAreaPicksTheOneShowingMostOfIt() {
    #expect(startingArea(last: nil, focusFrame: CGRect(x: 210, y: -2000, width: 500, height: 5000),
                         areas: [sidebar, list]) == list)
}
@Test func withNoLastAndNoFocusNothingIsOutlined() {
    #expect(startingArea(last: nil, focusFrame: nil, areas: [sidebar, list]) == nil)
    #expect(startingArea(last: nil, focusFrame: CGRect(x: 5000, y: 0, width: 10, height: 10), areas: [sidebar]) == nil)
}

// A line is about 60 px, sent as six small events; half the area's height likewise; the
// ends as one very large event. Positive is up.
@Test func wheelStepsForEachAmount() {
    #expect(ScrollAmount.line(.down).wheelSteps(areaHeight: 600) == Array(repeating: -10, count: 6))
    #expect(ScrollAmount.line(.up).wheelSteps(areaHeight: 600) == Array(repeating: 10, count: 6))
    #expect(ScrollAmount.half(.down).wheelSteps(areaHeight: 600) == Array(repeating: -50, count: 6))
    #expect(ScrollAmount.half(.up).wheelSteps(areaHeight: 125).reduce(0, +) == 63)   // rounded, nothing lost
    #expect(ScrollAmount.top.wheelSteps(areaHeight: 600) == [1_000_000])
    #expect(ScrollAmount.bottom.wheelSteps(areaHeight: 600) == [-1_000_000])
}

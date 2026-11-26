import Testing
import CoreGraphics
@testable import JumprCore

// JUM-120: labels on controls closer together than a label is wide covered each other.
// Crowded neighbours now get smaller labels in the same place.
//
// A two-letter label at 15 pt with a 9 pt advance is 27 x 20.
private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let fontSize: CGFloat = 15

private func layout() -> LabelLayout { LabelLayout(length: 2, fontSize: fontSize, advance: 9) }

private func full(_ target: CGRect, on s: CGRect = screen) -> CGRect {
    Labels.frame(length: 2, target: target, screen: s, fontSize: fontSize, advance: 9)
}

private func drawn(_ target: CGRect, at size: CGFloat, on s: CGRect = screen) -> CGRect {
    Labels.frame(length: 2, target: target, screen: s, fontSize: fontSize, advance: 9, drawnAt: size)
}

/// The ticket's rule: boxes overlapping by more than a tenth of the font size across and more
/// than two fifths of it down (the smaller of the two sizes) crowd each other.
private func crowd(_ a: CGRect, _ aSize: CGFloat, _ b: CGRect, _ bSize: CGFloat) -> Bool {
    let size = min(aSize, bSize)
    let across = min(a.maxX, b.maxX) - max(a.minX, b.minX)
    let down = min(a.maxY, b.maxY) - max(a.minY, b.minY)
    return across > size / 10 && down > size * 2 / 5
}

private func crowd(_ a: LabelLayout.Spot, _ b: LabelLayout.Spot) -> Bool {
    crowd(a.rect, a.size, b.rect, b.size)
}

/// Adds labels in order and keeps what is on screen, built only from what each `add` returned.
/// Checks on the way that an existing label is returned only when its spot changed.
private func show(_ labels: [(String, CGRect)], on s: CGRect = screen,
                  into l: inout LabelLayout, shown: inout [String: LabelLayout.Spot]) {
    for (letters, target) in labels {
        let changed = l.add(letters, target: target, screen: s)
        #expect(changed[letters] != nil, "the new label \(letters) is always returned")
        for (other, spot) in changed where other != letters {
            #expect(shown[other] != nil, "\(other) was never added")
            #expect(shown[other] != spot, "\(other) was returned although its spot did not change")
        }
        shown.merge(changed) { $1 }
    }
}

private func show(_ labels: [(String, CGRect)], on s: CGRect = screen) -> [String: LabelLayout.Spot] {
    var l = layout()
    var shown: [String: LabelLayout.Spot] = [:]
    show(labels, on: s, into: &l, shown: &shown)
    return shown
}

// Window buttons: 16 pt wide on a 23 pt pitch, so full-size labels (27 pt) overlap.
private let close = CGRect(x: 17, y: 49, width: 16, height: 16)
private let minimize = CGRect(x: 40, y: 49, width: 16, height: 16)
private let zoom = CGRect(x: 63, y: 49, width: 16, height: 16)
private let windowButtons = [("AA", close), ("AS", minimize), ("AD", zoom)]

// Two toolbar buttons with room between them: their labels never met before and must not change.
@Test func buttonsWithRoomBetweenThemKeepFullSizeLabels() {
    let left = CGRect(x: 100, y: 100, width: 20, height: 20)
    let right = CGRect(x: 140, y: 100, width: 20, height: 20)
    var l = layout()
    let first = l.add("AA", target: left, screen: screen)
    let second = l.add("AS", target: right, screen: screen)
    #expect(first == ["AA": LabelLayout.Spot(rect: full(left), size: 15)])
    #expect(second.keys.sorted() == ["AS"])
    #expect(second["AS"]?.rect == full(right))
    #expect(second["AS"]?.size == 15)
}

// Calculator, TextEdit and Clock: the close, minimize and zoom labels covered each other.
// Some apps report them close, zoom, minimize, so the result must not depend on order.
@Test func theThreeWindowButtonsGetOneSmallerSizeThatNoLongerCrowds() {
    let orders = [windowButtons, [windowButtons[0], windowButtons[2], windowButtons[1]],
                  windowButtons.reversed(), [windowButtons[1], windowButtons[0], windowButtons[2]]]
    for order in orders {
        let shown = show(order)
        #expect(shown.count == 3)
        let sizes = Set(shown.values.map(\.size))
        #expect(sizes.count == 1, "one size for all three, got \(sizes) for \(order.map(\.0))")
        guard let size = sizes.first else { continue }
        #expect(size >= 10 && size < 15)
        #expect(size == size.rounded(), "a whole-point size")
        for (letters, target) in order {
            guard let spot = shown[letters] else { continue }
            #expect(spot.rect == drawn(target, at: size))
            #expect(full(target).contains(spot.rect), "\(letters) stays within its full-size frame")
        }
        let a = shown["AA"]!, s = shown["AS"]!, d = shown["AD"]!
        #expect(!crowd(a, s)); #expect(!crowd(s, d)); #expect(!crowd(a, d))
        // The largest such size: one point larger, neighbours would crowd again.
        let up = size + 1
        #expect(crowd(drawn(close, at: up), up, drawn(minimize, at: up), up)
                || crowd(drawn(minimize, at: up), up, drawn(zoom, at: up), up))
    }
}

// TextEdit's formatting bar: bold, italic, underline and strikethrough about 20 pt apart,
// four labels piled up.
@Test func aRunOfFourFormattingButtonsIsDrawnAtOneSizeWithNoLabelCrowdingAnother() {
    let buttons = (0..<4).map { i in
        (["AA", "AS", "AD", "AF"][i], CGRect(x: 100 + CGFloat(i) * 20, y: 100, width: 20, height: 20))
    }
    let shown = show(buttons)
    let sizes = Set(shown.values.map(\.size))
    #expect(sizes.count == 1, "one size throughout the run, got \(sizes)")
    guard let size = sizes.first else { return }
    #expect(size >= 10 && size < 15)
    for (letters, target) in buttons { #expect(shown[letters]?.rect == drawn(target, at: size)) }
    for i in 0..<3 {
        #expect(!crowd(shown[buttons[i].0]!, shown[buttons[i + 1].0]!))
    }
    let up = size + 1
    #expect(crowd(drawn(buttons[0].1, at: up), up, drawn(buttons[1].1, at: up), up))
}

// Controls packed tighter than even a 10 pt label can clear. 10 pt is the smallest label
// size the settings allow, so it is the floor; crowding at 10 is accepted.
@Test func labelsAreNeverDrawnBelowTenPoints() {
    let a = CGRect(x: 100, y: 100, width: 8, height: 16)
    let b = CGRect(x: 108, y: 100, width: 8, height: 16)
    let shown = show([("AA", a), ("AS", b)])
    #expect(shown["AA"]?.size == 10)
    #expect(shown["AS"]?.size == 10)
    #expect(shown["AA"]?.rect == drawn(a, at: 10))
    #expect(shown["AS"]?.rect == drawn(b, at: 10))
}

// From the log: a row whose label sits inside its right end, and a button inside the row
// whose label hangs below it. The two boxes overlap 5 pt down, which only touches margins.
@Test func labelsThatOnlyTouchKeepFullSize() {
    let big = CGRect(x: 0, y: 0, width: 3000, height: 2000)
    let row = CGRect(x: 1576, y: 345, width: 288, height: 32)
    let button = CGRect(x: 1829, y: 351, width: 20, height: 20)
    #expect(full(row, on: big).intersects(full(button, on: big)), "the case only means something if they touch")
    var l = layout()
    _ = l.add("AA", target: row, screen: big)
    let second = l.add("AS", target: button, screen: big)
    #expect(second.keys.sorted() == ["AS"], "the row's label is left alone")
    #expect(second["AS"] == LabelLayout.Spot(rect: full(button, on: big), size: 15))
}

// Persistent mode takes a label away when its control goes. A label that is gone must not
// make the next one smaller.
@Test func aRemovedLabelNoLongerShrinksANewcomer() {
    var l = layout()
    _ = l.add("AA", target: close, screen: screen)
    l.remove("AA")
    let next = l.add("AS", target: minimize, screen: screen)
    #expect(next == ["AS": LabelLayout.Spot(rect: full(minimize), size: 15)])
}

@Test func removingLettersThatAreNotThereChangesNothing() {
    var l = layout()
    _ = l.add("AA", target: close, screen: screen)
    l.remove("ZZ")
    let next = l.add("AS", target: minimize, screen: screen)
    #expect((next["AS"]?.size ?? 15) < 15, "AA is still there and still crowds")
    #expect(next["AA"] != nil)
}

// A shrunken label does not grow back when the neighbour that shrank it goes.
@Test func aShrunkenLabelDoesNotGrowBackWhenItsNeighbourIsRemoved() {
    var l = layout()
    var shown: [String: LabelLayout.Spot] = [:]
    show(windowButtons, into: &l, shown: &shown)
    l.remove("AS")
    let far = l.add("QQ", target: CGRect(x: 500, y: 500, width: 16, height: 16), screen: screen)
    #expect(far.keys.sorted() == ["QQ"], "close and zoom keep their smaller spots")
    // Minimize comes back: it joins close and zoom at their size, and they stay as they were.
    let back = l.add("AS", target: minimize, screen: screen)
    #expect(back.keys.sorted() == ["AS"])
    #expect(back["AS"] == LabelLayout.Spot(rect: drawn(minimize, at: shown["AA"]!.size), size: shown["AA"]!.size))
}

// Shrinking the window buttons must not spread: a control elsewhere keeps its full label.
@Test func aLabelFarFromAShrunkenRunKeepsFullSize() {
    var l = layout()
    var shown: [String: LabelLayout.Spot] = [:]
    show(windowButtons, into: &l, shown: &shown)
    #expect(shown["AA"]!.size < 15)
    let target = CGRect(x: 500, y: 500, width: 16, height: 16)
    let far = l.add("QQ", target: target, screen: screen)
    #expect(far == ["QQ": LabelLayout.Spot(rect: full(target), size: 15)])
}

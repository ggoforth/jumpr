import Testing
import CoreGraphics
@testable import JumprCore

@Test func pressesWhenStillUnderItsLabel() {
    let drawn = CGRect(x: 10, y: 10, width: 40, height: 20)
    #expect(pressDecision(drawn: drawn, current: drawn) == .press)
    #expect(pressDecision(drawn: drawn, current: drawn.offsetBy(dx: 5, dy: 5)) == .press)
}

@Test func skipsWhenMovedAway() {
    let drawn = CGRect(x: 10, y: 10, width: 40, height: 20)
    #expect(pressDecision(drawn: drawn, current: drawn.offsetBy(dx: 0, dy: 300)) == .skip)
}

@Test func skipsWhenElementIsGone() {   // Review Focus 1
    #expect(pressDecision(drawn: CGRect(x: 10, y: 10, width: 40, height: 20), current: nil) == .skip)
}

@Test func clicksTheCenterOfTheVisiblePartAsItIsNow() {
    let visible = CGRect(x: 0, y: 0, width: 200, height: 20)   // scanned visible part of a wide text field
    let drawn = CGRect(x: 2, y: 2, width: 30, height: 16)      // its label, at the left edge
    #expect(clickPoint(visible: visible, drawn: drawn, current: visible) == CGPoint(x: 100, y: 10))
    // Element grew past the visible part (scrolled under a clip): stay inside what was visible.
    #expect(clickPoint(visible: visible, drawn: drawn, current: CGRect(x: 0, y: 0, width: 400, height: 20))
            == CGPoint(x: 100, y: 10))
}

@Test func clickFallsBackToTheLabelWhenTheVisiblePartIsGone() {
    let visible = CGRect(x: 0, y: 0, width: 10, height: 10)
    let drawn = CGRect(x: 0, y: 0, width: 30, height: 10)
    let current = CGRect(x: 20, y: 0, width: 40, height: 10)   // still under the label, not the old spot
    #expect(clickPoint(visible: visible, drawn: drawn, current: current) == CGPoint(x: 25, y: 5))
}

@Test func menuBarItemPressRelabels() {
    #expect(relabelsAfterPress(role: "AXMenuBarItem", result: .pressed, selected: false))
}

@Test func menuItemRelabelsOnlyWhenLeftSelected() {
    #expect(relabelsAfterPress(role: "AXMenuItem", result: .pressed, selected: true))
    #expect(!relabelsAfterPress(role: "AXMenuItem", result: .pressed, selected: false))
}

@Test func onlyAPressRelabels() {
    #expect(!relabelsAfterPress(role: "AXMenuBarItem", result: .clicked, selected: true))
    #expect(!relabelsAfterPress(role: "AXMenuBarItem", result: .skipped, selected: true))
    #expect(!relabelsAfterPress(role: "AXButton", result: .pressed, selected: true))
}

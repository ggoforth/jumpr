import Testing
import CoreGraphics
@testable import JumprCore

@Test func pressesWhenStillWhereItWasScanned() {
    let scanned = CGRect(x: 10, y: 10, width: 40, height: 20)
    #expect(pressDecision(scanned: scanned, current: scanned) == .press)
    #expect(pressDecision(scanned: scanned, current: scanned.offsetBy(dx: 5, dy: 5)) == .press)
}

@Test func pressesASmallTargetWhoseLabelHangsBesideIt() {
    // A menu bar icon: its label only touches its corner, so the label cannot be the reference.
    let icon = CGRect(x: 100, y: 0, width: 30, height: 24)
    let label = Labels.frame(length: 2, target: icon, screen: CGRect(x: 0, y: 0, width: 1000, height: 800),
                             fontSize: 15, advance: 9)
    #expect(!label.contains(CGPoint(x: icon.midX, y: icon.midY)))
    #expect(pressDecision(scanned: icon, current: icon) == .press)
    #expect(clickPoint(visible: icon, current: icon) == CGPoint(x: 115, y: 12))
}

@Test func skipsWhenMovedAway() {
    let scanned = CGRect(x: 10, y: 10, width: 40, height: 20)
    #expect(pressDecision(scanned: scanned, current: scanned.offsetBy(dx: 0, dy: 300)) == .skip)
    // A list scrolled by exactly one row: the row now sits where its neighbor was.
    #expect(pressDecision(scanned: scanned, current: scanned.offsetBy(dx: 0, dy: 20)) == .skip)
}

@Test func skipsWhenElementIsGone() {   // Review Focus 1
    #expect(pressDecision(scanned: CGRect(x: 10, y: 10, width: 40, height: 20), current: nil) == .skip)
}

@Test func clicksTheCenterOfTheVisiblePartAsItIsNow() {
    let visible = CGRect(x: 0, y: 0, width: 200, height: 20)   // scanned visible part of a wide text field
    #expect(clickPoint(visible: visible, current: visible) == CGPoint(x: 100, y: 10))
    // Element grew past the visible part (scrolled under a clip): stay inside what was visible.
    #expect(clickPoint(visible: visible, current: CGRect(x: 0, y: 0, width: 400, height: 20))
            == CGPoint(x: 100, y: 10))
    // Element shifted a little: the click lands on the part still in its old spot.
    #expect(clickPoint(visible: visible, current: visible.offsetBy(dx: 0, dy: 10)) == CGPoint(x: 100, y: 15))
}

@Test func clicksAtOnceWhenTheAppIsAlreadyInFront() {
    #expect(clickReadiness(appFrontmost: true, windowMain: true, waited: 0) == .ready)
    // A window that does not say whether it is main does not hold the click back.
    #expect(clickReadiness(appFrontmost: true, windowMain: nil, waited: 0) == .ready)
}

@Test func waitsForABackgroundAppToComeForwardBeforeClicking() {
    // Dia on another display while Claude is in front: 40 ms is not enough, so keep waiting.
    #expect(clickReadiness(appFrontmost: false, windowMain: true, waited: 0) == .wait)
    #expect(clickReadiness(appFrontmost: false, windowMain: true, waited: 0.04) == .wait)
    #expect(clickReadiness(appFrontmost: false, windowMain: true, waited: 0.3) == .wait)
    // In front, but another of its windows is still the main one.
    #expect(clickReadiness(appFrontmost: true, windowMain: false, waited: 0.1) == .wait)
    #expect(clickReadiness(appFrontmost: true, windowMain: true, waited: 0.12) == .ready)
}

@Test func givesUpWaitingAfterTheLimit() {
    #expect(clickReadiness(appFrontmost: false, windowMain: true, waited: 0.5) == .giveUp)
    #expect(clickReadiness(appFrontmost: true, windowMain: false, waited: 0.6) == .giveUp)
    #expect(clickReadiness(appFrontmost: false, windowMain: true, waited: 0.2, limit: 0.2) == .giveUp)
}

@Test func anAppThatDoesNotAnswerGetsTheOldFixedPause() {
    #expect(clickReadiness(appFrontmost: nil, windowMain: nil, waited: 0) == .wait)
    #expect(clickReadiness(appFrontmost: nil, windowMain: nil, waited: 0.04) == .ready)
}

@Test func menuItemRelabelsOnlyWhenLeftSelected() {
    #expect(relabelsAfterPress(role: "AXMenuItem", result: .pressed, selected: true))
    #expect(!relabelsAfterPress(role: "AXMenuItem", result: .pressed, selected: false))
}

@Test func menuBarItemRelabelsOnlyWhenLeftSelected() {   // extras open panels, not menus
    #expect(relabelsAfterPress(role: "AXMenuBarItem", result: .pressed, selected: true))
    #expect(!relabelsAfterPress(role: "AXMenuBarItem", result: .pressed, selected: false))
}

@Test func onlyAPressRelabels() {
    #expect(!relabelsAfterPress(role: "AXMenuBarItem", result: .clicked, selected: true))
    #expect(!relabelsAfterPress(role: "AXMenuBarItem", result: .skipped, selected: true))
    #expect(!relabelsAfterPress(role: "AXButton", result: .pressed, selected: true))
}

@Test func axPressSuccessCountsAsPressed() {
    #expect(afterAXPress(0) == .pressed)
}

@Test func axPressCannotCompleteCountsAsPressed() {   // the app is busy tracking a menu it opened
    #expect(afterAXPress(-25204) == .pressed)
}

@Test func axPressOnADeadElementSkips() {
    #expect(afterAXPress(-25202) == .skip)
}

@Test func axPressOtherFailuresFallBackToAClick() {
    #expect(afterAXPress(-25206) == .click)   // actionUnsupported
    #expect(afterAXPress(-25200) == .click)   // failure
    #expect(afterAXPress(-25205) == .click)   // attributeUnsupported / anything else
}

// Dia's web content answers "success" to an AXPress it does not offer, and nothing happens.

@Test func axPressIsUsedWhenTheElementOffersIt() {
    #expect(usesAXPress(role: "AXButton", actions: ["AXPress", "AXShowMenu"]))
}

@Test func axPressIsNotUsedWhenTheElementDoesNotOfferIt() {
    #expect(!usesAXPress(role: "AXLink", actions: ["AXShowMenu", "AXScrollToVisible"]))
    #expect(!usesAXPress(role: "AXRow", actions: []))
}

@Test func axPressIsTriedWhenTheActionsCouldNotBeRead() {
    #expect(usesAXPress(role: "AXButton", actions: nil))
}

@Test func textFieldsAlwaysGetAClick() {
    #expect(!usesAXPress(role: "AXTextField", actions: ["AXPress"]))
    #expect(!usesAXPress(role: "AXTextArea", actions: nil))
}

// Linear's sidebar lists AXPress, answers success, and does not navigate.
@Test func webContentAlwaysGetsAClick() {
    #expect(!usesAXPress(role: "AXButton", actions: ["AXPress", "AXShowMenu"], inWeb: true))
    #expect(!usesAXPress(role: "AXLink", actions: nil, inWeb: true))
    #expect(usesAXPress(role: "AXButton", actions: ["AXPress"], inWeb: false))
}

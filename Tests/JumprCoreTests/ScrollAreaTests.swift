import Testing
import CoreGraphics
@testable import JumprCore

private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
private let stack = WindowStack([Win(id: 1, pid: 10, name: "w", bounds: bounds, layer: 0, alpha: 1)])
private func areas(_ root: Fake, stack: WindowStack = stack) -> WalkResult {
    walk(root: root, pid: 10, scope: .window(id: 1, bounds: bounds, appWindows: [1]), stack: stack,
         deadline: 100, now: { 0 }, finding: .areas)
}
private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
private func focusableGroup(_ frame: CGRect, _ kids: [Fake] = []) -> Fake {
    let g = Fake("AXGroup", frame, kids); g.focusable = true
    return g
}

// Finder's file list is an `AXScrollArea` holding an outline.
@Test func aScrollAreaIsAnArea() {
    let list = Fake("AXScrollArea", r(200, 50, 600, 550), [Fake("AXOutline", r(200, 50, 600, 900))])
    let res = areas(Fake("AXWindow", bounds, [list]))
    #expect(res.areas == [Area(id: list.id, rect: r(200, 50, 600, 550), pid: 10, window: 1)])
}
// A page in a browser is an `AXWebArea`, with no scroll area around it in Chromium.
@Test func aWebPageIsAnArea() {
    let page = Fake("AXWebArea", r(0, 80, 800, 520))
    #expect(areas(Fake("AXWindow", bounds, [page])).areas.map(\.id) == [page.id])
}
// Electron apps and pages expose a scrolling region as a plain group that can take focus.
@Test func aGroupInWebContentThatCanTakeFocusIsAnArea() {
    let region = focusableGroup(r(300, 100, 400, 400))
    let plain = Fake("AXGroup", r(0, 100, 250, 400))
    let res = areas(Fake("AXWindow", bounds, [Fake("AXWebArea", r(0, 0, 800, 600), [region, plain])]))
    #expect(res.areas.map(\.id).contains(region.id))
    #expect(!res.areas.map(\.id).contains(plain.id))
}
@Test func aGroupOutsideWebContentIsNotAnAreaEvenIfItCanTakeFocus() {
    #expect(areas(Fake("AXWindow", bounds, [focusableGroup(r(0, 0, 400, 400))])).areas.isEmpty)
}
// A toolbar's tiny scroll area, or a strip of tags, is no place to scroll.
@Test func anAreaNeedsAtLeast80By80VisiblePoints() {
    let narrow = Fake("AXScrollArea", r(0, 0, 79, 400))
    let short = Fake("AXScrollArea", r(100, 0, 400, 79))
    let enough = Fake("AXScrollArea", r(100, 100, 80, 80))
    let mostlyOff = Fake("AXScrollArea", r(600, 540, 200, 400))   // 60 pt of it inside the window
    #expect(areas(Fake("AXWindow", bounds, [narrow, short, enough, mostlyOff])).areas.map(\.id) == [enough.id])
}
@Test func anAreaIsClippedToTheWindow() {
    let outer = Fake("AXScrollArea", r(0, 300, 400, 500))   // runs past the window's bottom
    #expect(areas(Fake("AXWindow", bounds, [outer])).areas.map(\.rect) == [r(0, 300, 400, 300)])
}
// Mail's message pane: one scroll area holds the header and the body, and the body's own
// scroll area runs past the pane's bottom. The body is the pane's content, scrolled by the
// pane ("the header and body scroll as one"): one area, the pane.
@Test func anAreaRunningPastTheAreaAroundItIsThatAreasContent() {
    let body = Fake("AXScrollArea", r(0, 136, 400, 960), [Fake("AXWebArea", r(0, 136, 400, 960))])
    let pane = Fake("AXScrollArea", r(0, 0, 400, 500), [body])
    #expect(areas(Fake("AXWindow", bounds, [pane])).areas.map(\.id) == [pane.id])
}
@Test func anAreaWhollyInsideAnotherOfADifferentSizeIsItsOwnArea() {
    let inner = Fake("AXScrollArea", r(0, 200, 400, 250))
    let outer = Fake("AXScrollArea", r(0, 0, 400, 500), [inner])
    #expect(areas(Fake("AXWindow", bounds, [outer])).areas.map(\.id) == [outer.id, inner.id])
}
@Test func anAreaUnderAnotherWindowIsNotAnArea() {
    let cover = Win(id: 2, pid: 20, name: "c", bounds: r(0, 0, 400, 600), layer: 0, alpha: 1)
    let under = Fake("AXScrollArea", r(0, 0, 300, 300)), beside = Fake("AXScrollArea", r(500, 0, 300, 300))
    let res = areas(Fake("AXWindow", bounds, [under, beside]), stack: WindowStack([cover] + stack.wins))
    #expect(res.areas.map(\.id) == [beside.id])
}
// Safari wraps its page in a scroll area of the same size: one area to a person, the inner one.
@Test func nestedAreasOfNearlyTheSameRectangleCollapseToTheInnermost() {
    let page = Fake("AXWebArea", r(3, 83, 794, 514))
    let region = focusableGroup(r(0, 80, 800, 520))
    let wrapper = Fake("AXScrollArea", r(0, 80, 800, 520), [Fake("AXGroup", r(0, 80, 800, 520), [page])])
    page.kids = [region]
    let res = areas(Fake("AXWindow", bounds, [wrapper]))
    #expect(res.areas.map(\.id) == [region.id])
    #expect(res.areas[0].rect == r(0, 80, 800, 520))
}
@Test func nestedAreasMoreThan6PointsApartAreBothKept() {
    let page = Fake("AXWebArea", r(0, 87, 800, 513))
    let wrapper = Fake("AXScrollArea", r(0, 80, 800, 520), [page])
    #expect(areas(Fake("AXWindow", bounds, [wrapper])).areas.map(\.id) == [wrapper.id, page.id])
}
@Test func sideBySideAreasOfTheSameSizeAreNotCollapsed() {   // only nested ones are one area
    let a = Fake("AXScrollArea", r(0, 0, 400, 300)), b = Fake("AXScrollArea", r(2, 2, 400, 300))
    #expect(areas(Fake("AXWindow", bounds, [a, b])).areas.map(\.id) == [a.id, b.id])
}
// A scan for areas never spends the extra request on text, and finds nothing to label.
@Test func lookingForAreasLabelsNothingAndAsksNothingExtra() {
    let text = Fake("AXStaticText", r(10, 10, 100, 20)); text.pressable = true
    let res = areas(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 40, 40, 20)), text]))
    #expect(res.targets.isEmpty)
    #expect(text.pressAsks == 0)
}
@Test func lookingForTargetsFindsNoAreas() {
    let res = walk(root: Fake("AXWindow", bounds, [Fake("AXScrollArea", r(0, 0, 400, 400))]), pid: 10,
                   scope: .window(id: 1, bounds: bounds, appWindows: [1]), stack: stack, deadline: 100, now: { 0 })
    #expect(res.areas.isEmpty)
}
@Test func theMenuBarAndTheDockHaveNoAreas() {
    let res = walk(root: Fake("AXList", r(0, 0, 400, 400), [Fake("AXScrollArea", r(0, 0, 400, 400))]), pid: 10,
                   scope: .system(screens: [bounds]), stack: stack, deadline: 100, now: { 0 }, finding: .areas)
    #expect(res.areas.isEmpty)
}

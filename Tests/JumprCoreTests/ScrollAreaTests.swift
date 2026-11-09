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
// Electron apps make every message keyboard-focusable so the arrow keys can move between
// them: in Claude and Discord each message is an article, in Slack a list's item. They are
// the content the region around them scrolls, not regions of their own.
@Test func anArticleOrAListsItemInWebContentIsNotAnAreaEvenIfItCanTakeFocus() {
    let article = focusableGroup(r(300, 100, 400, 150)); article.subrole = "AXDocumentArticle"
    let item = focusableGroup(r(300, 300, 400, 150))
    let list = Fake("AXList", r(300, 300, 400, 150), [item])
    let region = focusableGroup(r(300, 100, 400, 400), [article, list])
    let res = areas(Fake("AXWindow", bounds, [Fake("AXWebArea", r(0, 0, 800, 600), [region])]))
    #expect(res.areas.map(\.id).contains(region.id))
    #expect(!res.areas.map(\.id).contains(article.id))
    #expect(!res.areas.map(\.id).contains(item.id))
}
/// A scroll area that states how large its content is, as apps built with the iPad
/// frameworks and AppKit both do.
private func scrollArea(_ frame: CGRect, content: CGSize?, _ kids: [Fake] = []) -> Fake {
    let a = Fake("AXScrollArea", frame, kids); a.content = content
    return a
}
// Messages' emoji picker is a scroll area (320×355, content 320×19897) over a table whose
// first row holds the frequently-used emoji in a scroll area of their own (320×257,
// content 320×257), 5 pt below the picker's top-left corner. Both got a letter at one
// corner, and the outline framed the section, which has nothing to scroll.
@Test func aScrollAreaInsideAnotherWhoseContentIsNoTallerThanItIsNotAnArea() {
    let section = scrollArea(r(400, 105, 320, 257), content: CGSize(width: 320, height: 257),
                             [Fake("AXList", r(400, 105, 320, 257))])
    let row = Fake("AXRow", r(400, 102, 320, 263), [Fake("AXCell", r(400, 105, 320, 257), [section])])
    let picker = scrollArea(r(400, 100, 320, 355), content: CGSize(width: 320, height: 19897),
                            [Fake("AXTable", r(400, 100, 322, 19899), [row])])
    let res = areas(Fake("AXWindow", bounds, [picker]))
    #expect(res.areas.map(\.id) == [picker.id])
    #expect(picker.contentAsks == 0)   // asked of a scroll area inside another only
}
// Setapp's page (1384×1040) holds a row of screenshots that scrolls sideways only (1384×363,
// content 3064×363) and a list that scrolls on its own (1100×133, content 1100×208).
@Test func aScrollAreaInsideAnotherWithTallerContentIsStillAnArea() {
    let shelf = scrollArea(r(0, 100, 700, 180), content: CGSize(width: 1500, height: 180))
    let list = scrollArea(r(50, 400, 600, 133), content: CGSize(width: 600, height: 208))
    let page = scrollArea(r(0, 0, 700, 600), content: CGSize(width: 700, height: 1723), [shelf, list])
    #expect(areas(Fake("AXWindow", bounds, [page])).areas.map(\.id) == [page.id, list.id])
}
// Loopback's scroll area states no content size, and Finder's desktop states 0×0: neither
// says there is nothing to scroll.
@Test func aScrollAreaInsideAnotherThatStatesNoContentSizeIsStillAnArea() {
    let silent = scrollArea(r(0, 100, 300, 200), content: nil)
    let zero = scrollArea(r(350, 100, 300, 200), content: .zero)
    let page = scrollArea(r(0, 0, 700, 600), content: nil, [silent, zero])
    #expect(areas(Fake("AXWindow", bounds, [page])).areas.map(\.id) == [page.id, silent.id, zero.id])
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
// A browser window with another window over its middle: the page is still there to scroll,
// aimed at a part of it that shows, with its letter there too.
@Test func anAreaCoveredAtItsCenterIsAimedAtAVisiblePart() {
    let cover = Win(id: 2, pid: 20, name: "c", bounds: r(300, 0, 300, 600), layer: 0, alpha: 1)   // the middle third
    let page = Fake("AXWebArea", r(0, 0, 800, 600))
    let res = areas(Fake("AXWindow", bounds, [page]), stack: WindowStack([cover] + stack.wins))
    #expect(res.areas.map(\.id) == [page.id])
    let aim = res.areas[0].aim
    #expect(!cover.bounds.contains(aim) && page.frame!.contains(aim))
    #expect(res.areas[0].anchor == CGPoint(x: 0, y: 0))   // the top-left corner shows, so the letter goes there
}
@Test func anAreaWhoseTopLeftIsCoveredPutsItsLetterAtTheAim() {
    let cover = Win(id: 2, pid: 20, name: "c", bounds: r(0, 0, 200, 200), layer: 0, alpha: 1)   // the corner
    let page = Fake("AXWebArea", r(0, 0, 800, 600))
    let res = areas(Fake("AXWindow", bounds, [page]), stack: WindowStack([cover] + stack.wins))
    #expect(res.areas[0].aim == CGPoint(x: 400, y: 300))
    #expect(res.areas[0].anchor == res.areas[0].aim)
}
@Test func anUncoveredAreaIsAimedAtItsCenterAndLetteredAtItsCorner() {
    let list = Fake("AXScrollArea", r(200, 50, 600, 550))
    let a = areas(Fake("AXWindow", bounds, [list])).areas[0]
    #expect(a.aim == CGPoint(x: 500, y: 325) && a.anchor == CGPoint(x: 200, y: 50))
}
// Messages: both panes are plain groups that offer the page-scroll actions, outside web
// content, and neither has a scroll role. Asking costs a request, so only groups outside
// any area found are asked, and never in web content.
@Test func aGroupOutsideWebContentThatOffersPageScrollingIsAnArea() {
    let list = Fake("AXGroup", r(0, 0, 327, 600)); list.pagesByAction = true
    let inner = Fake("AXGroup", r(0, 0, 327, 600)); inner.pagesByAction = true   // nested, same size: not asked
    list.kids = [inner]
    let transcript = Fake("AXGroup", r(327, 0, 473, 600)); transcript.pagesByAction = true
    let plain = Fake("AXGroup", r(0, 0, 800, 600), [list, transcript])
    let res = areas(Fake("AXWindow", bounds, [plain]))
    #expect(res.areas.map(\.id) == [list.id, transcript.id])
    #expect(inner.pageAsks == 0 && plain.pageAsks == 1)
}
// Messages: the transcript's group reports the whole window as its frame, and the
// conversation list sits over its left third. Both were found, but their letters landed on
// the same corner and the outline covered the window. The larger area keeps the part the
// smaller one leaves free: its letter and its aim move there.
@Test func anAreaLaidOverByASmallerOneKeepsThePartLeftFree() {
    let list = Fake("AXGroup", r(0, 0, 327, 600)); list.pagesByAction = true
    let transcript = Fake("AXGroup", r(0, 0, 800, 600)); transcript.pagesByAction = true
    let res = areas(Fake("AXWindow", bounds, [Fake("AXGroup", bounds, [list, transcript])]))
    #expect(res.areas.map(\.id) == [list.id, transcript.id])
    #expect(res.areas[1].rect == r(327, 0, 473, 600))
    #expect(res.areas[1].anchor == CGPoint(x: 327, y: 0))
    #expect(res.areas[1].aim == CGPoint(x: 563.5, y: 300))
}
@Test func anAreaWithNothingLeftFreeBesideASmallerOneIsDropped() {
    let over = Fake("AXScrollArea", r(0, 0, 798, 598)), under = Fake("AXScrollArea", r(0, 0, 800, 600))
    let res = areas(Fake("AXWindow", bounds, [Fake("AXGroup", bounds, [over, under])]))
    #expect(res.areas.map(\.id) == [over.id])
}
@Test func groupsInWebContentAndSmallGroupsAreNotAskedAboutPageScrolling() {
    let web = Fake("AXGroup", r(0, 0, 400, 400)); web.pagesByAction = true
    let small = Fake("AXGroup", r(500, 0, 60, 60)); small.pagesByAction = true
    let res = areas(Fake("AXWindow", bounds, [Fake("AXWebArea", r(0, 0, 400, 600), [web]), small]))
    #expect(!res.areas.map(\.id).contains(web.id) && !res.areas.map(\.id).contains(small.id))
    #expect(web.pageAsks == 0 && small.pageAsks == 0)
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

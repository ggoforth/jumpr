import Testing
import CoreGraphics
@testable import JumprCore

final class Fake: AXNode {
    let id: ElementID
    var role: String; var frame: CGRect?; var enabled: Bool? = true
    var kids: [Fake]; var selected = false; var rows: [Fake]?; var visibleKids: [Fake]?
    var pressable = false
    var focusable = false
    var subrole: String?
    private(set) var infoCalls = 0
    private(set) var pressAsks = 0
    private static var next = 0
    init(_ role: String, _ frame: CGRect? = nil, _ kids: [Fake] = []) {
        Fake.next += 1; id = ElementID(Fake.next)
        self.role = role; self.frame = frame; self.kids = kids
    }
    func info() -> NodeInfo? {
        infoCalls += 1
        return NodeInfo(role: role, frame: frame, enabled: enabled, children: kids, focusable: focusable, subrole: subrole)
    }
    func isSelected() -> Bool { selected }
    func visibleRows() -> [any AXNode]? { rows }
    func visibleChildren() -> [any AXNode]? { visibleKids }
    func offersPress() -> Bool { pressAsks += 1; return pressable }
    var pagesByAction = false
    private(set) var pageAsks = 0
    func offersPageScroll() -> Bool { pageAsks += 1; return pagesByAction }
}
/// Text that says it can be pressed, as Messages' sidebar items do.
private func pressableText(_ frame: CGRect) -> Fake {
    let t = Fake("AXStaticText", frame); t.pressable = true
    return t
}
private let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
private let stack = WindowStack([Win(id: 1, pid: 10, name: "w", bounds: bounds, layer: 0, alpha: 1)])
private func run(_ root: Fake, deadline: Double = 100, now: @escaping () -> Double = { 0 },
                 scope: WalkScope = .window(id: 1, bounds: bounds, appWindows: [1])) -> WalkResult {
    walk(root: root, pid: 10, scope: scope, stack: stack, deadline: deadline, now: now)
}
private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 40, _ h: CGFloat = 20) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

@Test func labelsClickableRolesOnly() {
    let res = run(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10)), Fake("AXStaticText", r(10, 40)), Fake("AXLink", r(10, 70))]))
    #expect(res.targets.map(\.role) == ["AXButton", "AXLink"])
    #expect(res.nodes == 4)
    #expect(res.targets.allSatisfy { $0.window == 1 && $0.pid == 10 })
}
@Test func prunesSubtreeOutsideClip() {
    let hidden = Fake("AXButton", r(10, 10))
    let off = Fake("AXGroup", CGRect(x: 0, y: 900, width: 400, height: 100), [hidden])
    let res = run(Fake("AXWindow", bounds, [off]))
    #expect(res.targets.isEmpty)
    #expect(hidden.infoCalls == 0)
}
@Test func scrollAreaNarrowsClipAndTrimsRect() {
    let half = Fake("AXButton", CGRect(x: 10, y: 90, width: 40, height: 20))   // half below the scroll area
    let below = Fake("AXButton", r(10, 150))
    let scroll = Fake("AXScrollArea", CGRect(x: 0, y: 0, width: 400, height: 100), [half, below])
    let res = run(Fake("AXWindow", bounds, [scroll]))
    #expect(res.targets.count == 1)
    #expect(res.targets[0].rect == CGRect(x: 10, y: 90, width: 40, height: 10))
}
// Messages' emoji picker opens above the compose field's button at the window's right
// edge and reaches 335 pt past it, drawn in a helper window of its own. Clipped to the
// window's bounds, the walk found a sliver of the popover and nothing in it.
@Test func aPopoverHangingOutsideItsWindowIsWalkedWhole() {
    let outside = Fake("AXButton", r(500, 150))
    let popover = Fake("AXPopover", CGRect(x: 350, y: 100, width: 300, height: 200), [outside])
    let helper = Win(id: 3, pid: 10, name: "p", bounds: popover.frame!, layer: 0, alpha: 1)
    let res = walk(root: Fake("AXWindow", bounds, [popover]), pid: 10, scope: .window(id: 1, bounds: bounds, appWindows: [1]),
                   stack: WindowStack([helper] + stack.wins), deadline: 100, now: { 0 })
    #expect(res.targets.map(\.id) == [outside.id])
    #expect(res.targets.first?.rect == r(500, 150))
}
@Test func doesNotDescendIntoLeafControls() {
    let inner = Fake("AXLink", r(12, 12, 10, 10))
    let res = run(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10), [inner])]))
    #expect(res.targets.count == 1)
    #expect(inner.infoCalls == 0)
}
@Test func skipsDisabledAndTiny() {
    let off = Fake("AXButton", r(10, 10)); off.enabled = false
    let res = run(Fake("AXWindow", bounds, [off, Fake("AXButton", r(10, 40, 3, 3))]))
    #expect(res.targets.isEmpty)
}
@Test func menusOnlyDescendWhenSelected() {
    let item = Fake("AXMenuItem", r(10, 30))
    let menu = Fake("AXMenu", r(10, 30, 100, 100), [item])
    let closed = Fake("AXMenuBarItem", r(10, 0), [menu])
    let res1 = run(Fake("AXMenuBar", r(0, 0, 400, 24), [closed]), scope: .system(screens: [bounds]))
    #expect(res1.targets.map(\.role) == ["AXMenuBarItem"])
    closed.selected = true
    let res2 = run(Fake("AXMenuBar", r(0, 0, 400, 24), [closed]), scope: .system(screens: [bounds]))
    #expect(res2.targets.map(\.role) == ["AXMenuBarItem", "AXMenuItem"])
    #expect(res2.targets.allSatisfy { $0.window == nil })
}
@Test func tablesUseVisibleRowsAndSkipColumns() {
    let row1 = Fake("AXRow", r(0, 0, 400, 20)), row2 = Fake("AXRow", r(0, 20, 400, 20))
    let column = Fake("AXColumn", r(0, 0, 100, 400), [Fake("AXButton", r(5, 5))])
    let table = Fake("AXTable", bounds, [row1, row2, column]); table.rows = [row1]
    #expect(run(Fake("AXWindow", bounds, [table])).targets.map(\.id) == [row1.id])
    table.rows = nil
    #expect(run(Fake("AXWindow", bounds, [table])).targets.map(\.id) == [row1.id, row2.id])
}
// Messages' emoji picker: the Smileys section is a grid that reports a 320×444 frame but
// holds 482 buttons laid out over 3400 px, so the clip cannot prune it, and reading every
// off-screen button ran the app out of its budget after the two rows on screen. The grid
// says which 18 children show.
@Test func aGridIsWalkedThroughItsVisibleChildrenOnly() {
    let shown = Fake("AXButton", r(0, 0, 47, 42)), hidden = Fake("AXButton", r(0, 3000, 47, 42))
    let grid = Fake("AXGrid", r(0, 0, 320, 444), [shown, hidden]); grid.visibleKids = [shown]
    #expect(run(Fake("AXWindow", bounds, [grid])).targets.map(\.id) == [shown.id])
    #expect(hidden.infoCalls == 0)
}
@Test func aGridThatNamesNoVisibleChildrenIsWalkedWhole() {
    let a = Fake("AXButton", r(0, 0, 47, 42)), b = Fake("AXButton", r(50, 0, 47, 42))
    let grid = Fake("AXGrid", r(0, 0, 320, 444), [a, b])
    #expect(run(Fake("AXWindow", bounds, [grid])).targets.map(\.id) == [a.id, b.id])
    grid.visibleKids = []
    #expect(run(Fake("AXWindow", bounds, [grid])).targets.map(\.id) == [a.id, b.id])
}
// Messages' emoji picker: each section is a table row holding the section's grid or list.
// The row is clickable by role, so it got a label of its own at its right end, beside the
// labels on the emoji that fill it. No single emoji covers half the row; together they do.
@Test func aRowWhoseInnerLabelsTogetherCoverHalfOfItGetsNoLabel() {
    let cells = (0..<6).map { Fake("AXButton", r(CGFloat($0) * 50, 0, 47, 45)) }
    let row = Fake("AXRow", r(0, 0, 320, 45), cells)
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == cells.map(\.id))
}
@Test func aRowWithOneSmallControlInsideKeepsItsLabel() {   // a checkbox at the edge of a wide row
    let box = Fake("AXCheckBox", r(4, 4, 16, 16))
    let row = Fake("AXRow", r(0, 0, 320, 24), [box])
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == [row.id, box.id])
}
@Test func coveredElementsAreNotLabeled() {
    let cover = Win(id: 2, pid: 20, name: "c", bounds: CGRect(x: 0, y: 0, width: 200, height: 400), layer: 0, alpha: 1)
    let res = walk(root: Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10)), Fake("AXButton", r(300, 10))]),
                   pid: 10, scope: .window(id: 1, bounds: bounds, appWindows: [1]),
                   stack: WindowStack([cover] + stack.wins), deadline: 100, now: { 0 })
    #expect(res.targets.map(\.rect.minX) == [300])
}
@Test func systemScopeRequiresAScreen() {
    let res = run(Fake("AXList", nil, [Fake("AXDockItem", r(10, 10)), Fake("AXDockItem", r(9000, 10))]), scope: .system(screens: [bounds]))
    #expect(res.targets.count == 1)
}
@Test func stopsAtDeadlineWithPartialResults() {   // Review Focus 2: hung or huge app
    var t = 0.0
    let kids = (0..<50).map { Fake("AXButton", r(10, CGFloat($0 * 5))) }
    let res = run(Fake("AXWindow", bounds, kids), deadline: 10, now: { t += 1; return t })
    #expect(res.timedOut)
    #expect(res.targets.count > 0 && res.targets.count < 50)
}
@Test func depthIsCapped() {
    var node = Fake("AXButton", r(10, 10))
    for _ in 0..<100 { node = Fake("AXGroup", nil, [node]) }
    #expect(run(node).targets.isEmpty)
}

/// A button under `depth` groups: the root group is depth 0, so the button is at `depth`.
private func buttonAt(depth: Int) -> Fake {
    var node = Fake("AXButton", r(10, 10))
    for _ in 0..<depth { node = Fake("AXGroup", nil, [node]) }
    return node
}
@Test func depthCapBoundary() {   // the walk stops at depth 80
    #expect(run(buttonAt(depth: 79)).targets.count == 1)
    #expect(run(buttonAt(depth: 80)).targets.isEmpty)
}

// Chrome with its page tree off still answers with its toolbar (about 60 nodes), so the
// sign of a missing page is nothing to click in web content, not an empty window.
@Test func webTreeIsEmptyWhenAWalkedWindowGaveNothingToClickInWebContent() {
    #expect(webTreeLooksEmpty(walkedWindow: true, webTargets: 0))
}
@Test func webTreeIsNotEmptyWithSomethingToClickInWebContent() {
    #expect(!webTreeLooksEmpty(walkedWindow: true, webTargets: 1))
    #expect(!webTreeLooksEmpty(walkedWindow: true, webTargets: 129))
}
@Test func webTreeIsUndecidedWithNoWindowWalked() {   // hidden, or on another Space
    #expect(!webTreeLooksEmpty(walkedWindow: false, webTargets: 0))
}

// A browser that took `AXManualAccessibility` moments ago may still be building: wait for
// its second scan. One that refused it (Chrome) has nothing to wait for.
@Test func theHeavierRequestWaitsOnlyForATreeAlreadyAskedFor() {
    #expect(!mayAskForEnhancedTree(scan: 1, manualAccepted: true))
    #expect(mayAskForEnhancedTree(scan: 2, manualAccepted: true))
    #expect(mayAskForEnhancedTree(scan: 1, manualAccepted: false))
    #expect(mayAskForEnhancedTree(scan: 5, manualAccepted: false))
}

// Web content (browsers, Electron apps) answers "success" to a press and may do nothing.
@Test func targetsUnderAWebAreaAreMarkedAsWeb() {
    let web = Fake("AXWebArea", bounds, [Fake("AXGroup", bounds, [Fake("AXLink", r(10, 40))])])
    let res = run(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10)), web]))
    #expect(res.targets.map(\.role) == ["AXButton", "AXLink"])
    #expect(res.targets.map(\.inWeb) == [false, true])
}

@Test func countsWebAreas() {
    let web = Fake("AXWebArea", bounds, [Fake("AXLink", r(10, 40))])
    #expect(run(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10)), web])).webAreas == 1)
    #expect(run(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10))])).webAreas == 0)
    #expect(run(Fake("AXWindow", bounds, [Fake("AXWebArea", bounds)])).webAreas == 1)   // empty: still counted
}

// Mail's message body: the first scan found no links, the next found ten.
@Test func aWebViewWithNothingToClickMayStillBeBuilding() {
    #expect(webViewMayStillBeBuilding(hostsWeb: true, webTargets: 0, sinceTrigger: 0))
    #expect(webViewMayStillBeBuilding(hostsWeb: true, webTargets: 0, sinceTrigger: 1.2))
    #expect(!webViewMayStillBeBuilding(hostsWeb: true, webTargets: 0, sinceTrigger: 1.3))   // waited long enough
    #expect(!webViewMayStillBeBuilding(hostsWeb: true, webTargets: 10, sinceTrigger: 0))    // already built
    #expect(!webViewMayStillBeBuilding(hostsWeb: false, webTargets: 0, sinceTrigger: 0))    // no web view: nothing to wait for
    #expect(webViewMayStillBeBuilding(hostsWeb: true, webTargets: 0, sinceTrigger: 2, allow: 3))
}

@Test func aTreeSwitchedOnMomentsAgoMayStillBeBuilding() {
    #expect(treeMayStillBeBuilding(sinceSwitchedOn: 0))
    #expect(treeMayStillBeBuilding(sinceSwitchedOn: 1.5))    // 1Password: still empty containers
    #expect(!treeMayStillBeBuilding(sinceSwitchedOn: 3))
    #expect(!treeMayStillBeBuilding(sinceSwitchedOn: 600))
    #expect(!treeMayStillBeBuilding(sinceSwitchedOn: nil))   // native app: nothing to wait for
    #expect(treeMayStillBeBuilding(sinceSwitchedOn: 4, allow: 5))
}

// System Settings' sidebar: a row and the button filling it got two labels 17 pt apart.
@Test func aRowFilledByAButtonIsLabeledOnceOnTheButton() {
    let button = Fake("AXButton", r(0, 0, 400, 24))
    let row = Fake("AXRow", r(0, 0, 400, 24), [Fake("AXCell", r(0, 0, 400, 24), [button])])
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == [button.id])
}
@Test func aRowKeepsItsLabelBesideASmallControlAtItsEdge() {
    let check = Fake("AXCheckBox", r(4, 4, 16, 16))
    let row = Fake("AXRow", r(0, 0, 400, 24), [check])
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == [row.id, check.id])
}
@Test func aRowWithNothingClickableInsideKeepsItsLabel() {
    let row = Fake("AXRow", r(0, 0, 400, 24), [Fake("AXCell", r(0, 0, 400, 24), [Fake("AXStaticText", r(0, 0, 400, 24))])])
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == [row.id])
}
@Test func theInnerControlWinsFromHalfTheRowsArea() {
    let half = Fake("AXButton", r(0, 0, 200, 24)), less = Fake("AXButton", r(0, 24, 199, 24))
    let rows = [Fake("AXRow", r(0, 0, 400, 24), [half]), Fake("AXRow", r(0, 24, 400, 24), [less])]
    #expect(run(Fake("AXWindow", bounds, rows)).targets.map(\.id) == [half.id, rows[1].id, less.id])
}
// Messages' sidebar: each conversation and each pin is text that offers a press, not a row
// or a button, and none of them got a label.
@Test func textThatOffersAPressIsLabeled() {
    let pin = pressableText(r(10, 10, 95, 115)), conversation = pressableText(r(10, 140, 300, 79))
    let plain = Fake("AXStaticText", r(10, 230))
    let res = run(Fake("AXWindow", bounds, [Fake("AXGroup", bounds, [pin, conversation, plain])]))
    #expect(res.targets.map(\.id) == [pin.id, conversation.id])
    #expect(res.targets.allSatisfy { $0.role == "AXStaticText" && !$0.inWeb })
}
// Asking is one more request per element, so it is not spent where the answer cannot matter.
@Test func textInsideSomethingAlreadyLabeledIsNotAsked() {   // Finder and Mail: every row holds text
    let text = pressableText(r(0, 0, 400, 24))
    let row = Fake("AXRow", r(0, 0, 400, 24), [Fake("AXCell", r(0, 0, 400, 24), [text])])
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == [row.id])
    #expect(text.pressAsks == 0)
}
@Test func textInWebContentIsNotAsked() {   // a long page holds thousands of text nodes
    let text = pressableText(r(10, 40))
    let res = run(Fake("AXWindow", bounds, [Fake("AXWebArea", bounds, [Fake("AXGroup", bounds, [text])])]))
    #expect(res.targets.isEmpty)
    #expect(text.pressAsks == 0)
}
@Test func textThatCouldNotBeLabeledIsNotAsked() {
    let off = pressableText(r(10, 10)); off.enabled = false
    let tiny = pressableText(r(10, 40, 3, 3)), noFrame = pressableText(.zero)
    let res = run(Fake("AXWindow", bounds, [off, tiny, noFrame]))
    #expect(res.targets.isEmpty)
    #expect([off, tiny, noFrame].allSatisfy { $0.pressAsks == 0 })
}
@Test func otherRolesAreNeverAsked() {   // in Messages even plain groups offer a press
    let group = Fake("AXGroup", r(10, 10, 200, 200)); group.pressable = true
    #expect(run(Fake("AXWindow", bounds, [group])).targets.isEmpty)
    #expect(group.pressAsks == 0)
}
// Dia's sidebar: each folder is a child of the list with no role (`AXUnknown`), no children
// and no actions. None of them got a label.
@Test func aListsItemsWithNoRoleAreLabeled() {
    let folders = [Fake("AXUnknown", r(0, 0, 270, 39)), Fake("AXUnknown", r(0, 40, 270, 39))]
    let res = run(Fake("AXWindow", bounds, [Fake("AXList", bounds, folders)]))
    #expect(res.targets.map(\.id) == folders.map(\.id))
    #expect(res.targets.allSatisfy { $0.role == "AXUnknown" })
}
@Test func elementsWithNoRoleOutsideAListAreNotLabeled() {
    let loose = Fake("AXUnknown", r(0, 0, 270, 39))
    let deeper = Fake("AXList", bounds, [Fake("AXGroup", bounds, [Fake("AXUnknown", r(0, 40, 270, 39))])])   // not the list's own item
    #expect(run(Fake("AXWindow", bounds, [loose, deeper])).targets.isEmpty)
}
// Messages' emoji picker: each frequently-used emoji is an element with no role that offers
// a press, under a disabled group under the section's list, so not the list's own item. The
// section is a table row, labelled by role, and the row's label kept the emoji from being
// asked, the way text under a row is not asked. Here the emoji get the labels and the row,
// filled by them, loses its own.
@Test func elementsWithNoRoleThatOfferAPressAreLabeledEvenUnderALabeledRow() {
    let emoji = (0..<6).map { i -> Fake in
        let e = Fake("AXUnknown", r(12 + CGFloat(i) * 50, 3, 47, 45)); e.pressable = true
        return e
    }
    let wrappers = emoji.map { e -> Fake in let g = Fake("AXGroup", e.frame!, [e]); g.enabled = false; return g }
    let list = Fake("AXList", r(0, 0, 320, 51), wrappers)
    let row = Fake("AXRow", r(0, 0, 320, 51), [Fake("AXCell", r(0, 3, 320, 45), [Fake("AXScrollArea", r(0, 3, 320, 45), [list])])])
    #expect(run(Fake("AXWindow", bounds, [row])).targets.map(\.id) == emoji.map(\.id))
}
@Test func anElementWithNoRoleIsNotAskedForAPressInWebContent() {
    let inWeb = Fake("AXUnknown", r(12, 12, 47, 45)); inWeb.pressable = true
    let res = run(Fake("AXWindow", bounds, [Fake("AXWebArea", r(0, 0, 400, 200), [inWeb])]))
    #expect(res.targets.isEmpty)
    #expect(inWeb.pressAsks == 0)
}
@Test func aListInWebContentIsLeftAlone() {   // a page's lists hold links, which have their own role
    let list = Fake("AXList", bounds, [Fake("AXUnknown", r(0, 0, 270, 39))])
    #expect(run(Fake("AXWindow", bounds, [Fake("AXWebArea", bounds, [list])])).targets.isEmpty)
}
// Dia's "New Tab" item holds a button of the same size: one label, on the button.
@Test func aListItemFilledByAButtonIsLabeledOnceOnTheButton() {
    let button = Fake("AXButton", r(0, 0, 270, 39))
    let list = Fake("AXList", bounds, [Fake("AXUnknown", r(0, 0, 270, 39), [button])])
    #expect(run(Fake("AXWindow", bounds, [list])).targets.map(\.id) == [button.id])
}
// An open folder's item also spans the tabs in it, which are the list's next items. Its
// label and its click belong on the folder's own line, the part the tabs leave free.
@Test func anOpenFoldersItemIsTrimmedToThePartItsTabsLeaveFree() {
    let folder = Fake("AXUnknown", r(0, 0, 270, 76)), tab = Fake("AXRadioButton", r(15, 34, 251, 39))
    let res = run(Fake("AXWindow", bounds, [Fake("AXList", bounds, [folder, tab])]))
    #expect(res.targets.map(\.id) == [folder.id, tab.id])
    #expect(res.targets[0].rect == r(0, 0, 270, 34))
    #expect(res.targets[1].rect == r(15, 34, 251, 39))
}
@Test func aListItemEntirelyUnderOtherLabelsGetsNone() {
    let item = Fake("AXUnknown", r(0, 0, 270, 39)), over = Fake("AXButton", r(0, 0, 270, 39))
    #expect(run(Fake("AXWindow", bounds, [Fake("AXList", bounds, [item, over])])).targets.map(\.id) == [over.id])
}
@Test func theLargestFreeBandIsWhatIsLeftBesideWhatCoversIt() {
    let whole = r(0, 0, 270, 76)
    #expect(largestFreeBand(of: whole, around: []) == whole)
    #expect(largestFreeBand(of: whole, around: [r(0, 100, 270, 39)]) == whole)                 // does not touch it
    #expect(largestFreeBand(of: whole, around: [r(15, 34, 251, 39)]) == r(0, 0, 270, 34))      // the band above
    #expect(largestFreeBand(of: whole, around: [r(0, 0, 270, 20)]) == r(0, 20, 270, 56))       // the band below
    #expect(largestFreeBand(of: whole, around: [r(250, 0, 20, 76)]) == r(0, 0, 250, 76))       // the band to the left
    #expect(largestFreeBand(of: whole, around: [whole]) == nil)
    #expect(largestFreeBand(of: whole, around: [r(0, 3, 270, 70)]) == nil)                     // what is left is under 4 pt
}
// A date picker on a web page: each day is plain text in a list, with no role that says it
// can be clicked. What sets it apart from the text around it is that it can take keyboard
// focus. None of the days got a label.
@Test func textOnAWebPageThatCanTakeFocusIsLabeled() {
    let day = Fake("AXStaticText", r(10, 40, 40, 39)); day.focusable = true
    let past = Fake("AXStaticText", r(50, 40, 40, 39)); past.focusable = true; past.enabled = false   // a day that cannot be picked
    let heading = Fake("AXStaticText", r(10, 10, 117, 19))
    let picker = Fake("AXList", bounds, [Fake("AXGroup", bounds, [heading, day, past])])
    let res = run(Fake("AXWindow", bounds, [Fake("AXWebArea", bounds, [picker])]))
    #expect(res.targets.map(\.id) == [day.id])
    #expect(res.targets[0].inWeb)
}
@Test func otherThingsOnAWebPageThatCanTakeFocusAreNotLabeled() {   // scrolling regions, splitters, toolbars
    let region = Fake("AXGroup", r(10, 10, 300, 300)); region.focusable = true
    let splitter = Fake("AXSplitter", r(320, 10, 19, 300)); splitter.focusable = true
    #expect(run(Fake("AXWindow", bounds, [Fake("AXWebArea", bounds, [region, splitter])])).targets.isEmpty)
}
@Test func outsideWebContentFocusIsNotTheSign() {   // there, text says so by offering a press
    let text = Fake("AXStaticText", r(10, 10)); text.focusable = true
    #expect(run(Fake("AXWindow", bounds, [text])).targets.isEmpty)
}
@Test func nestedRowsCollapseToTheInnermostControl() {
    let button = Fake("AXButton", r(20, 0, 380, 24))
    let inner = Fake("AXRow", r(20, 0, 380, 24), [button])
    let outer = Fake("AXRow", r(0, 0, 400, 24), [Fake("AXDisclosureTriangle", r(2, 4, 16, 16)), inner])
    #expect(run(Fake("AXWindow", bounds, [outer])).targets.map(\.role) == ["AXDisclosureTriangle", "AXButton"])
}

// Notification Center presents a notification as a plain group, which is only told apart
// from every other group by its subrole. The group offers the press; the text in it does not.
@Test func aNotificationAndAStackOfThemAreLabeledOnce() {
    let one = Fake("AXGroup", r(10, 10, 344, 75), [Fake("AXStaticText", r(60, 20, 100, 16))])
    one.subrole = "AXNotificationCenterBanner"
    let stacked = Fake("AXGroup", r(10, 100, 344, 58), [Fake("AXStaticText", r(60, 110, 100, 16))])
    stacked.subrole = "AXNotificationCenterBannerStack"
    let res = run(Fake("AXWindow", bounds, [one, stacked]))
    #expect(res.targets.map(\.id) == [one.id, stacked.id])
    #expect(res.targets.allSatisfy { $0.role == "AXGroup" })
}
// In apps built with the iPad frameworks plain groups offer a press too, and labelling
// those would flood the screen.
@Test func aGroupWithAnotherSubroleStaysUnlabeled() {
    let host = Fake("AXGroup", r(10, 10, 344, 75))
    host.subrole = "AXHostingView"
    host.pressable = true
    #expect(run(Fake("AXWindow", bounds, [host])).targets.isEmpty)
}

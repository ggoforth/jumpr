import Testing
import CoreGraphics
@testable import JumprCore

final class Fake: AXNode {
    let id: ElementID
    var role: String; var frame: CGRect?; var enabled: Bool? = true
    var kids: [Fake]; var selected = false; var rows: [Fake]?
    private(set) var infoCalls = 0
    private static var next = 0
    init(_ role: String, _ frame: CGRect? = nil, _ kids: [Fake] = []) {
        Fake.next += 1; id = ElementID(Fake.next)
        self.role = role; self.frame = frame; self.kids = kids
    }
    func info() -> NodeInfo? { infoCalls += 1; return NodeInfo(role: role, frame: frame, enabled: enabled, children: kids) }
    func isSelected() -> Bool { selected }
    func visibleRows() -> [any AXNode]? { rows }
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

// The walk counts each window's root node, so an empty web tree shows as one node per window.
@Test func webTreeIsEmptyWhenWindowsGaveOnlyTheirRoots() {
    #expect(webTreeLooksEmpty(windowsScanned: 1, windowNodes: 1))
    #expect(webTreeLooksEmpty(windowsScanned: 3, windowNodes: 3))
    #expect(webTreeLooksEmpty(windowsScanned: 2, windowNodes: 0))
}
@Test func webTreeIsNotEmptyWithMoreThanTheRoots() {
    #expect(!webTreeLooksEmpty(windowsScanned: 1, windowNodes: 2))
    #expect(!webTreeLooksEmpty(windowsScanned: 2, windowNodes: 40))
}
@Test func webTreeIsUndecidedWithNoWindowScanned() {
    #expect(!webTreeLooksEmpty(windowsScanned: 0, windowNodes: 0))
}

// Web content (browsers, Electron apps) answers "success" to a press and may do nothing.
@Test func targetsUnderAWebAreaAreMarkedAsWeb() {
    let web = Fake("AXWebArea", bounds, [Fake("AXGroup", bounds, [Fake("AXLink", r(10, 40))])])
    let res = run(Fake("AXWindow", bounds, [Fake("AXButton", r(10, 10)), web]))
    #expect(res.targets.map(\.role) == ["AXButton", "AXLink"])
    #expect(res.targets.map(\.inWeb) == [false, true])
}

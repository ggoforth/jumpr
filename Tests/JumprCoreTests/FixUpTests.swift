import Testing
import CoreGraphics
@testable import JumprCore

private func t(_ id: Int, _ x: CGFloat) -> Target {
    Target(id: ElementID(id), rect: CGRect(x: x, y: 0, width: 40, height: 20), role: "AXButton", pid: 10, window: 1)
}

@Test func unchangedProducesNothing() {
    #expect(fixUp(shown: [Shown(label: "AA", target: t(1, 0))], fresh: [t(1, 0)]) == FixUp(remove: [], move: [], add: []))
}

@Test func goneMovedAndNew() {
    let shown = [Shown(label: "AA", target: t(1, 0)), Shown(label: "AS", target: t(2, 50)), Shown(label: "AD", target: t(3, 100))]
    let fresh = [t(2, 80), t(3, 100), t(4, 150), t(5, 200)]
    let f = fixUp(shown: shown, fresh: fresh)
    #expect(f.remove == ["AA"])
    #expect(f.move == [Moved(label: "AS", target: t(2, 80))])
    #expect(f.add == [t(4, 150), t(5, 200)])
}

@Test func emptyFreshRemovesEverything() {
    #expect(fixUp(shown: [Shown(label: "AA", target: t(1, 0))], fresh: []).remove == ["AA"])
}

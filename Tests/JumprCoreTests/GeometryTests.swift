import Testing
import CoreGraphics
@testable import JumprCore

private func w(_ id: WindowID, _ pid: Int32, _ r: CGRect, layer: Int = 0, alpha: Double = 1) -> Win {
    Win(id: id, pid: pid, name: "w\(id)", bounds: r, layer: layer, alpha: alpha)
}
private let a = w(1, 10, CGRect(x: 0, y: 0, width: 100, height: 100))
private let b = w(2, 20, CGRect(x: 50, y: 0, width: 100, height: 100))

@Test func topIsFrontmostContaining() {
    let s = WindowStack([a, b])
    #expect(s.top(at: CGPoint(x: 75, y: 50))?.id == 1)
    #expect(s.top(at: CGPoint(x: 120, y: 50))?.id == 2)
    #expect(s.top(at: CGPoint(x: 500, y: 500)) == nil)
}
@Test func nonOccludersAreIgnored() {
    let dock = w(9, 99, CGRect(x: 0, y: 0, width: 200, height: 200), layer: 20)
    let ghost = w(8, 98, CGRect(x: 0, y: 0, width: 200, height: 200), alpha: 0)
    let widget = w(7, 97, CGRect(x: 0, y: 0, width: 200, height: 200), layer: -5)
    #expect(WindowStack([dock, ghost, widget, b]).top(at: CGPoint(x: 120, y: 50))?.id == 2)
}
@Test func visibleOnlyWhereOwnWindowIsOnTop() {
    let s = WindowStack([a, b])
    #expect(s.isVisible(CGPoint(x: 120, y: 50), window: 2, pid: 20, appWindows: [2]))
    #expect(!s.isVisible(CGPoint(x: 75, y: 50), window: 2, pid: 20, appWindows: [2]))
}
@Test func helperWindowOfSameAppCounts() {
    let popover = w(3, 20, CGRect(x: 110, y: 10, width: 30, height: 30))
    let s = WindowStack([popover, a, b])
    let p = CGPoint(x: 120, y: 20)
    #expect(s.isVisible(p, window: 2, pid: 20, appWindows: [2]))       // 3 is a helper
    #expect(!s.isVisible(p, window: 2, pid: 20, appWindows: [2, 3]))   // 3 is a real window
}
@Test func anyVisibleUsesFiveByFiveGrid() {
    let cover = w(4, 30, CGRect(x: 0, y: 0, width: 400, height: 400))
    #expect(!WindowStack([cover, b]).anyVisible(2))
    #expect(WindowStack([a, b]).anyVisible(2))
    #expect(!WindowStack([a]).anyVisible(2))   // not on screen at all
}

import CoreGraphics
import Testing
@testable import JumprCore

private func target(_ id: Int, x: CGFloat = 0, pid: Int32 = 10, window: WindowID? = 5) -> Target {
    Target(id: ElementID(id), rect: CGRect(x: x, y: 0, width: 20, height: 20), role: "AXButton", pid: pid, window: window)
}
private func win(_ id: WindowID, pid: Int32, _ r: CGRect) -> Win {
    Win(id: id, pid: pid, name: "", bounds: r, layer: 0, alpha: 1)
}

// A page reloads under a toolbar: the toolbar's button keeps its letters, the old link goes, the new one is added.
@Test func reconcileKeepsRemovesAndAdds() {
    var r = Reconcile(placed: [ElementID(1): ("AS", target(1).rect), ElementID(2): ("AD", target(2).rect)])
    #expect(r.note(target(1)) == .keep)
    #expect(r.note(target(3)) == .add)
    #expect(r.removals() == ["AD"])
    #expect(r.kept == 1)
}

// The page scrolls a little after the press: same button, new place, same letters.
@Test func anElementThatMovedKeepsItsLetters() {
    var r = Reconcile(placed: [ElementID(1): ("AS", target(1).rect)])
    #expect(r.note(target(1, x: 40)) == .move(label: "AS"))
    #expect(r.removals() == [])
    #expect(r.kept == 0)
}

// A busy app ran out of budget halfway: what it did not reach is not known to be gone.
@Test func aScanThatWasNotCompleteNeverRemoves() {
    var r = Reconcile(placed: [ElementID(1): ("AS", target(1).rect), ElementID(2): ("AD", target(2).rect)])
    _ = r.note(target(1))
    r.noteIncomplete()
    #expect(!r.complete)
    #expect(r.removals() == [])
}

// An element named by two window results is one element.
@Test func anElementSeenTwiceIsKeptOnce() {
    var r = Reconcile(placed: [ElementID(1): ("AS", target(1).rect)])
    _ = r.note(target(1))
    #expect(r.note(target(1)) == .keep)
    #expect(r.kept == 1)
}

// A press in Safari opens a window over Finder. Finder was not scanned, so geometry decides.
@Test func aLabelIsDroppedWhenAWindowNowCoversItsTarget() {
    let t = target(1)
    let behind = win(5, pid: 10, CGRect(x: 0, y: 0, width: 100, height: 100))
    let over = win(6, pid: 20, CGRect(x: 0, y: 0, width: 50, height: 50))
    #expect(coveredLabels(["AS": t], stack: WindowStack([behind]), scanned: []) == [])
    #expect(coveredLabels(["AS": t], stack: WindowStack([over, behind]), scanned: []) == ["AS"])
    #expect(coveredLabels(["AS": t], stack: WindowStack([over]), scanned: []) == ["AS"])        // its window is gone
    #expect(coveredLabels(["AS": t], stack: WindowStack([over, behind]), scanned: [10]) == [])  // scanned: Reconcile decides
}

// Menu bar, extras and Dock targets have no window; geometry cannot judge them.
@Test func aLabelWithNoWindowIsKept() {
    let over = win(6, pid: 20, CGRect(x: 0, y: 0, width: 500, height: 500))
    #expect(coveredLabels(["AS": target(1, window: nil)], stack: WindowStack([over]), scanned: []) == [])
}

// A popover Safari opens over its own window is a helper window with no labels: Safari's
// labels under it stay, as they did when it was scanned.
@Test func anUnlabelledWindowOfTheSameAppDoesNotCoverItsLabels() {
    let t = target(1)
    let main = win(5, pid: 10, CGRect(x: 0, y: 0, width: 100, height: 100))
    let popover = win(7, pid: 10, CGRect(x: 0, y: 0, width: 50, height: 50))
    #expect(coveredLabels(["AS": t], stack: WindowStack([popover, main]), scanned: []) == [])
}

// Two Finder windows, both labelled: the one brought forward hides the other's labels.
@Test func aLabelledWindowOfTheSameAppCoversItsSiblingsLabels() {
    let behind = target(1, window: 5)
    let front = target(2, x: 200, window: 7)
    let back = win(5, pid: 10, CGRect(x: 0, y: 0, width: 100, height: 100))
    let sibling = win(7, pid: 10, CGRect(x: 0, y: 0, width: 300, height: 100))
    #expect(coveredLabels(["AS": behind, "AD": front], stack: WindowStack([sibling, back]), scanned: []) == ["AS"])
}

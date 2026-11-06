import Testing
import CoreGraphics
@testable import JumprCore

@Test func lengthHasHeadroom() {
    #expect(Labels.length(forEstimate: 0) == 1)
    #expect(Labels.length(forEstimate: 17) == 1)    // 25.5 → 26
    #expect(Labels.length(forEstimate: 18) == 2)
    #expect(Labels.length(forEstimate: 450) == 2)   // 675
    #expect(Labels.length(forEstimate: 451) == 3)
}

@Test func poolIsOrderedFixedLengthAndFinite() {
    var p = LabelPool(length: 2)
    #expect(p.next() == "AA"); #expect(p.next() == "AS"); #expect(p.next() == "AD")
    var all: Set<String> = ["AA", "AS", "AD"]
    while let l = p.next() { #expect(l.count == 2); #expect(all.insert(l).inserted) }
    #expect(all.count == 676)
    #expect(p.next() == nil)                        // overflow: extras go unlabeled
    var one = LabelPool(length: 1)
    #expect((0..<26).compactMap { _ in one.next() }.joined() == "ASDFGHJKLQWERTYUIOPZXCVBNM")
}

// A two-letter label at 15 pt with a 9 pt advance is 27 x 20.
private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private func frame(_ target: CGRect) -> CGRect {
    Labels.frame(length: 2, target: target, screen: screen, fontSize: 15, advance: 9)
}

@Test func smallTargetKeepsItsLabelOffTheBottomRightCorner() {
    // A menu bar icon: the label overlaps the corner by 11 x 6 pt and leaves the rest visible.
    let icon = CGRect(x: 100, y: 0, width: 30, height: 24)
    let label = frame(icon)
    #expect(label == CGRect(x: 119, y: 18, width: 27, height: 20))
    let covered = label.intersection(icon)
    #expect(covered.width * covered.height < icon.width * icon.height / 10)
    // A short target gives up no more than a quarter of its height.
    #expect(frame(CGRect(x: 100, y: 100, width: 40, height: 20)) == CGRect(x: 129, y: 115, width: 27, height: 20))
    // A tiny target gives up no more than half of its width.
    #expect(frame(CGRect(x: 100, y: 100, width: 10, height: 10)) == CGRect(x: 105, y: 107.5, width: 27, height: 20))
}

@Test func largeTargetKeepsItsLabelInsideAtTheRightEnd() {
    // A list row: inside, so stacked rows never share a label; at the right, clear of the text's start.
    let row = CGRect(x: 100, y: 100, width: 200, height: 20)
    #expect(frame(row) == CGRect(x: 271, y: 100, width: 27, height: 20))
    #expect(row.contains(frame(row)))
    // Room for two label heights: tucked into the bottom-right corner.
    #expect(frame(CGRect(x: 100, y: 100, width: 300, height: 200)) == CGRect(x: 371, y: 278, width: 27, height: 20))
    // Just under four label widths still counts as small.
    #expect(frame(CGRect(x: 100, y: 100, width: 107, height: 20)).minX == 196)
}

@Test func labelFlipsAwayFromAScreenEdgeInsteadOfCoveringItsTarget() {
    // Bottom edge (a Dock icon): above the target.
    let dock = CGRect(x: 500, y: 760, width: 40, height: 40)
    #expect(frame(dock) == CGRect(x: 529, y: 746, width: 27, height: 20))
    // Right edge (the clock): to the left.
    #expect(frame(CGRect(x: 970, y: 0, width: 30, height: 24)) == CGRect(x: 954, y: 18, width: 27, height: 20))
    // The corner: both, and still on the screen.
    let corner = frame(CGRect(x: 990, y: 790, width: 10, height: 10))
    #expect(corner == CGRect(x: 968, y: 772.5, width: 27, height: 20))
    #expect(screen.contains(corner))
    // A target bigger than the screen still gets a label on it.
    #expect(screen.contains(frame(CGRect(x: -50, y: -50, width: 2000, height: 2000))))
}

@Test func screenIndexIsNilOffEveryDisplay() {   // Review Focus 4
    let screens = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: -100, y: 0, width: 100, height: 100)]
    #expect(Labels.screenIndex(for: CGPoint(x: -50, y: 50), screens: screens) == 1)
    #expect(Labels.screenIndex(for: CGPoint(x: 500, y: 50), screens: screens) == nil)
}

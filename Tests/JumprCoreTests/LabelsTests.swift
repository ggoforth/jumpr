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

@Test func framePlacement() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let small = Labels.frame(length: 2, target: CGRect(x: 100, y: 100, width: 40, height: 20), screen: screen, fontSize: 15, advance: 9)
    #expect(small == CGRect(x: 106.5, y: 100, width: 27, height: 20))
    let wide = Labels.frame(length: 2, target: CGRect(x: 100, y: 100, width: 200, height: 20), screen: screen, fontSize: 15, advance: 9)
    #expect(wide.minX == 102)
    let edge = Labels.frame(length: 2, target: CGRect(x: 990, y: 790, width: 10, height: 10), screen: screen, fontSize: 15, advance: 9)
    #expect(screen.contains(edge))
}

@Test func screenIndexIsNilOffEveryDisplay() {   // Review Focus 4
    let screens = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: -100, y: 0, width: 100, height: 100)]
    #expect(Labels.screenIndex(for: CGPoint(x: -50, y: 50), screens: screens) == 1)
    #expect(Labels.screenIndex(for: CGPoint(x: 500, y: 50), screens: screens) == nil)
}

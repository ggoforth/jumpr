import Testing
import CoreGraphics
@testable import JumprCore

private let all: (Due) -> Bool = { _ in true }

private func tg(_ n: Int) -> [Target] {
    (0..<n).map { i in
        Target(id: ElementID(i), rect: CGRect(x: Double(i) * 20, y: 0, width: 10, height: 10),
               role: "AXButton", pid: 10, window: 1)
    }
}

private func near(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-6
}

@Test func neverThenCleanThenStale() {
    let c = CacheStore()
    #expect(c.served(1) == .never)
    c.changed(window: 1, pid: 10, at: 0)
    #expect(c.served(1) == .never)                      // known about, never scanned
    c.scanStarted(window: 1, pid: 10, at: 0.3)
    c.scanFinished(window: 1, pid: 10, targets: tg(3), startedAt: 0.3, at: 0.35, background: true, failed: false)
    #expect(c.served(1) == .clean(tg(3)))
    #expect(c.count(1) == 3)
    c.changed(window: 1, pid: 10, at: 5)
    #expect(c.served(1) == .stale)
    #expect(c.count(1) == 3)                            // stale count still feeds the estimate
}
@Test func burstSettlesIntoOneScan() {
    let c = CacheStore()
    for t in stride(from: 0.0, through: 1.0, by: 0.1) { c.changed(window: 1, pid: 10, at: t) }
    #expect(c.due(at: 1.2, warm: all).isEmpty)          // still settling
    #expect(near(c.nextWake(after: 1.2, warm: all), 1.3))
    #expect(c.due(at: 1.31, warm: all) == [Due(window: 1, pid: 10)])
}
@Test func coldWindowsAreNotScanned() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0)
    #expect(c.due(at: 10, warm: { _ in false }).isEmpty)
    #expect(c.nextWake(after: 10, warm: { _ in false }) == nil)
}
@Test func spacingIsTwentyTimesScanTimeAndAtLeastOneSecond() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.3)
    c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: 0.3, at: 0.4, background: true, failed: false)   // 0.1 s scan → next at 2.4
    c.changed(window: 1, pid: 10, at: 1.5)
    #expect(c.due(at: 1.9, warm: all).isEmpty)          // settled, but spaced
    #expect(near(c.nextWake(after: 1.9, warm: all), 2.4))
    #expect(c.due(at: 2.41, warm: all).count == 1)

    let d = CacheStore()
    d.changed(window: 1, pid: 10, at: 0)
    d.scanStarted(window: 1, pid: 10, at: 0.3)
    d.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: 0.3, at: 0.31, background: true, failed: false)  // 10 ms scan → floor 1 s → 1.31
    d.changed(window: 1, pid: 10, at: 0.5)
    #expect(d.due(at: 1.0, warm: all).isEmpty)
    #expect(d.due(at: 1.32, warm: all).count == 1)
}
@Test func foregroundScansDoNotStartTheSpacingClock() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.1)
    c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: 0.1, at: 0.2, background: false, failed: false)
    c.changed(window: 1, pid: 10, at: 0.3)
    #expect(c.due(at: 0.61, warm: all).count == 1)
}
@Test func oneScanPerAppAtATime() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0); c.changed(window: 2, pid: 10, at: 0)
    #expect(c.due(at: 0.31, warm: all).count == 2)
    c.scanStarted(window: 1, pid: 10, at: 0.31)
    #expect(c.due(at: 0.4, warm: all).isEmpty)
}
@Test func changeDuringScanLeavesItStale() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.3)
    c.changed(window: 1, pid: 10, at: 0.32)
    c.scanFinished(window: 1, pid: 10, targets: tg(2), startedAt: 0.3, at: 0.35, background: true, failed: false)
    #expect(c.served(1) == .stale)
    #expect(c.count(1) == 2)
}
@Test func restlessWindowIsGivenUpOnThenResumed() {
    let c = CacheStore()
    var t = 0.0
    c.changed(window: 1, pid: 10, at: t)
    for _ in 0..<3 {                                    // re-scan, then stale again 0.5 s later, three times
        c.scanStarted(window: 1, pid: 10, at: t)
        c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: t, at: t + 0.01, background: false, failed: false)
        t += 0.5
        c.changed(window: 1, pid: 10, at: t)
    }
    #expect(c.isRestless(1))
    #expect(c.due(at: t + 0.31, warm: all).isEmpty)     // settle alone no longer enough
    #expect(c.due(at: t + 2.01, warm: all).count == 1)  // quiet for 2 s
    c.scanStarted(window: 1, pid: 10, at: t + 2.01)
    c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: t + 2.01, at: t + 2.02, background: true, failed: false)
    #expect(!c.isRestless(1))                           // a clean scan ends it and resets the strikes
}
@Test func pressJumpsTheQueueAndIgnoresSpacing() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.3)
    c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: 0.3, at: 0.8, background: true, failed: false)   // 0.5 s scan → spaced until 10.8
    c.changed(window: 2, pid: 20, at: 0.9)
    c.pressed(window: 1, pid: 10, at: 1.0)
    #expect(c.served(1) == .stale)
    #expect(c.due(at: 1.05, warm: all).isEmpty)
    #expect(c.due(at: 1.11, warm: all) == [Due(window: 1, pid: 10)])          // no change reported → 100 ms
    c.changed(window: 1, pid: 10, at: 1.08)
    #expect(!c.due(at: 1.15, warm: all).contains(Due(window: 1, pid: 10)))    // now waits for its changes to settle
    #expect(c.due(at: 1.39, warm: all) == [Due(window: 1, pid: 10), Due(window: 2, pid: 20)])   // priority sorts first
}
@Test func failedScanKeepsOldTargetsAndBacksOff() {   // Review Focus 2
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.3)
    c.scanFinished(window: 1, pid: 10, targets: [], startedAt: 0.3, at: 0.8, background: true, failed: true)
    #expect(c.served(1) == .never)
    #expect(c.due(at: 5, warm: all).isEmpty)            // 0.5 s × 20 = 10 s back-off
    #expect(c.due(at: 10.81, warm: all).count == 1)
}
@Test func goneWindowsAndAppsAreForgotten() {         // Review Focus 1
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0); c.changed(window: 2, pid: 10, at: 0); c.changed(window: 3, pid: 30, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.3)
    c.windowGone(3)
    c.appGone(pid: 10)
    #expect(c.due(at: 5, warm: all).isEmpty)
    #expect(c.nextWake(after: 5, warm: all) == nil)
    #expect(c.served(1) == .never)
}
@Test func restlessWindowStillRespectsAppSpacing() {
    let c = CacheStore()
    var t = 0.0
    c.changed(window: 1, pid: 10, at: t)
    for _ in 0..<3 {                                    // make window 1 restless with foreground scans
        c.scanStarted(window: 1, pid: 10, at: t)
        c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: t, at: t + 0.01, background: false, failed: false)
        t += 0.5
        c.changed(window: 1, pid: 10, at: t)
    }
    #expect(c.isRestless(1))                            // t = 1.5, quiet until 3.5
    c.changed(window: 2, pid: 10, at: 1.5)
    c.scanStarted(window: 2, pid: 10, at: 1.5)
    c.scanFinished(window: 2, pid: 10, targets: tg(1), startedAt: 1.5, at: 2.0, background: true, failed: false)   // 0.5 s scan → spaced until 12.0
    #expect(c.due(at: 3.51, warm: all).isEmpty)         // quiet, but the app is spaced
    #expect(near(c.nextWake(after: 3.51, warm: all), 12.0))
    #expect(c.due(at: 12.01, warm: all) == [Due(window: 1, pid: 10)])
}
@Test func pressDuringScanIsKept() {
    let c = CacheStore()
    c.scanStarted(window: 1, pid: 10, at: 0)
    c.pressed(window: 1, pid: 10, at: 0.05)
    c.scanFinished(window: 1, pid: 10, targets: tg(2), startedAt: 0, at: 0.1, background: true, failed: false)
    #expect(c.served(1) == .stale)                      // the scan saw the window before the press
    #expect(c.count(1) == 2)
    #expect(c.due(at: 0.14, warm: all).isEmpty)
    #expect(near(c.nextWake(after: 0.1, warm: all), 0.15))   // still priority: pressedAt + afterPress, spacing ignored
    #expect(c.due(at: 0.16, warm: all) == [Due(window: 1, pid: 10)])
}
@Test func overlappingScansOfOneAppAreCounted() {
    let c = CacheStore()
    c.changed(window: 1, pid: 10, at: 0); c.changed(window: 2, pid: 10, at: 0)
    c.scanStarted(window: 1, pid: 10, at: 0.3)          // foreground
    c.scanStarted(window: 1, pid: 10, at: 0.3)          // background, overlapping
    c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: 0.3, at: 0.4, background: false, failed: false)
    #expect(c.due(at: 0.5, warm: all).isEmpty)          // one scan of pid 10 still running
    c.scanFinished(window: 1, pid: 10, targets: tg(1), startedAt: 0.3, at: 0.45, background: false, failed: false)
    #expect(c.due(at: 0.5, warm: all) == [Due(window: 2, pid: 10)])
}

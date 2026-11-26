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
// Jumpr's own panel, open under its menu bar icon, sits at the status layer (25), not a
// normal one. Labels for the app behind it were drawn on top of the panel.
@Test func aMenuBarAppsPanelHidesWhatIsBehindIt() {
    let panel = w(5, 30, CGRect(x: 60, y: 0, width: 80, height: 90), layer: 25)
    let s = WindowStack([panel, b])
    #expect(s.top(at: CGPoint(x: 120, y: 50))?.id == 5)
    #expect(!s.isVisible(CGPoint(x: 120, y: 50), window: 2, pid: 20, appWindows: [2]))
    #expect(s.isVisible(CGPoint(x: 145, y: 50), window: 2, pid: 20, appWindows: [2]))   // beside the panel
}
@Test func theLayersAroundTheStatusLayerStillDoNotHide() {   // the menu bar (24), anything above
    let menuBar = w(6, 40, CGRect(x: 0, y: 0, width: 200, height: 200), layer: 24)
    let above = w(7, 41, CGRect(x: 0, y: 0, width: 200, height: 200), layer: 26)
    #expect(WindowStack([above, menuBar, b]).top(at: CGPoint(x: 120, y: 50))?.id == 2)
}
// Notification Center's open sidebar is one transparent window across the whole display, at
// layer 21. A click anywhere outside the sidebar only closes it, so nothing behind it counts
// as reachable, and the sidebar itself has to count as visible for a scan to walk it.
@Test func theSidebarIsVisibleAndHidesTheWindowsBehindIt() {
    let sidebar = w(8, 50, CGRect(x: 0, y: 0, width: 200, height: 200), layer: 21)
    let s = WindowStack([sidebar, b])
    #expect(s.anyVisible(8))
    #expect(!s.anyVisible(2))
    #expect(s.isVisible(CGPoint(x: 120, y: 50), window: 8, pid: 50, appWindows: [8]))
}
// A notification banner is shown in the same layer-21 window as the open sidebar, across the
// whole 3440×1440 display, transparent outside a 344×58 banner at 3080,46. Every window on that
// display lost its labels while it showed, though a click outside the banner lands on the
// window behind. Asking the window server about every control cost 384 questions per trigger
// at about 290 µs each (106 on the main thread), and triggers went from 67–80 ms to 109–135 ms,
// so it is asked once per window list, at the 5×5 grid `anyVisible` samples (573×240 apart).
private let display = CGRect(x: 0, y: 0, width: 3440, height: 1440)
private let ncWindow = w(12, 70, display, layer: 21)
private let behindNC = w(13, 80, display)
private let realBanner = CGRect(x: 3080, y: 46, width: 344, height: 58)
private let bannerCentre = CGPoint(x: 3252, y: 75)
private func landsOnNC(inside region: CGRect) -> (CGPoint) -> WindowID? {
    { region.contains($0) ? ncWindow.id : behindNC.id }
}

@Test func clicksPassThroughAWindowWhoseBannerNoSamplePointLandsOn() {
    #expect(clicksPassThrough(ncWindow, clickLandsOn: landsOnNC(inside: realBanner)))
}
// A stack of banners can catch one or two of the grid's samples. This region holds the
// samples (2866.7, 240) and (2866.7, 480), and clicks still pass through everywhere else.
@Test func clicksPassThroughAWindowWhoseBannersCatchOnlyAFewSamplePoints() {
    let stack = CGRect(x: 2850, y: 46, width: 574, height: 454)
    #expect(clicksPassThrough(ncWindow, clickLandsOn: landsOnNC(inside: stack)))
}
// The open sidebar (JUM-98): a click anywhere in the window lands on it, all 25 samples.
@Test func clicksDoNotPassThroughTheOpenSidebar() {
    #expect(!clicksPassThrough(ncWindow, clickLandsOn: { _ in ncWindow.id }))
}
@Test func withABannerUpTheWindowBehindKeepsItsLabels() {
    let s = WindowStack([ncWindow, behindNC], clickThrough: [ncWindow.id])
    let p = CGPoint(x: 1720, y: 720)
    #expect(s.anyVisible(behindNC.id))
    #expect(s.isVisible(p, window: behindNC.id, pid: behindNC.pid, appWindows: [behindNC.id]))
    #expect(s.top(at: p)?.id == behindNC.id)
}
// The scan has to walk Notification Center's window for its banner to get a label.
@Test func withABannerUpTheBannerIsVisibleToAScan() {
    let s = WindowStack([ncWindow, behindNC], clickThrough: [ncWindow.id])
    #expect(s.anyVisible(ncWindow.id))
    #expect(s.isVisible(bannerCentre, window: ncWindow.id, pid: ncWindow.pid, appWindows: [ncWindow.id]))
}
// A menu bar app's panel (layer 25) open over the banner still hides it there.
@Test func aClickThroughWindowIsHiddenWhereAWindowInFrontOfItHidesIt() {
    let panel = w(14, 90, CGRect(x: 3200, y: 0, width: 200, height: 150), layer: 25)
    let s = WindowStack([panel, ncWindow, behindNC], clickThrough: [ncWindow.id])
    #expect(!s.isVisible(bannerCentre, window: ncWindow.id, pid: ncWindow.pid, appWindows: [ncWindow.id]))
}
@Test func theLayersAroundTheSidebarStillDoNotHide() {   // the Dock (20), and nothing seen at 22
    let dock = w(9, 60, CGRect(x: 0, y: 0, width: 200, height: 200), layer: 20)
    let above = w(10, 61, CGRect(x: 0, y: 0, width: 200, height: 200), layer: 22)
    #expect(WindowStack([above, dock, b]).top(at: CGPoint(x: 120, y: 50))?.id == 2)
}
// Desktop widgets belong to Notification Center too, far below every window.
@Test func theDesktopLayerIsNotVisibleToAScan() {
    let widget = w(11, 50, CGRect(x: 0, y: 0, width: 180, height: 180), layer: -2147483601)
    #expect(!WindowStack([widget]).anyVisible(11))
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

@Test func windowFramesMatchWithinOnePoint() {
    let f = CGRect(x: 100, y: 200, width: 800, height: 600)
    #expect(sameWindowFrame(f, f))
    // AX rounds differently from the window server: each edge may be off by up to 1 pt.
    #expect(sameWindowFrame(f, CGRect(x: 101, y: 199, width: 798, height: 602)))
    #expect(sameWindowFrame(f, CGRect(x: 99.5, y: 200.5, width: 801, height: 599)))
}

@Test func windowFramesDoNotMatchBeyondOnePoint() {
    let f = CGRect(x: 100, y: 200, width: 800, height: 600)
    #expect(!sameWindowFrame(f, CGRect(x: 102, y: 200, width: 800, height: 600)))       // left + right edge off by 2
    #expect(!sameWindowFrame(f, CGRect(x: 100, y: 200, width: 802, height: 600)))       // right edge off by 2
    #expect(!sameWindowFrame(f, CGRect(x: 100, y: 200, width: 800, height: 601.5)))     // bottom edge off by 1.5
}

// A window the window server names by ID, or whose frame matches one of the app's on-screen
// windows, is scanned.
@Test func aWindowNamedByIDOrByFrameIsScanned() {
    #expect(windowNaming(idFound: true, frameAnswered: false, frameMatches: false) == .named)
    #expect(windowNaming(idFound: false, frameAnswered: true, frameMatches: true) == .named)
}

// Finder lists its desktop in AXWindows: an AXScrollArea (subrole AXDesktop) the size of all
// displays together. It has no window ID, it answers its frame, and no on-screen window has
// that frame, so every persistent-mode reconcile of Finder came out incomplete and removed
// nothing. Nothing on screen can hold a label for it, so it is not a window Jumpr failed to read.
@Test func anEntryThatAnswersItsFrameAndMatchesNoWindowIsNotAWindow() {
    #expect(windowNaming(idFound: false, frameAnswered: true, frameMatches: false) == .notOnScreen)
}

// A window whose frame request timed out may still have labels on screen: the scan that
// skipped it must not remove them.
@Test func anEntryWhoseFrameDidNotAnswerIsUnread() {
    #expect(windowNaming(idFound: false, frameAnswered: false, frameMatches: false) == .unread)
}

// Jumpr's own windows stay in the snapshot: Settings (layer 0) hides what is behind it,
// the label overlays (layer 1000) do not.
private let me: Int32 = 77
@Test func ownNormalWindowOccludesTheAppBehind() {
    let settings = w(5, me, CGRect(x: 60, y: 10, width: 40, height: 40))
    let s = WindowStack([settings, b])
    #expect(!s.isVisible(CGPoint(x: 80, y: 30), window: 2, pid: 20, appWindows: [2]))
    #expect(s.isVisible(CGPoint(x: 120, y: 80), window: 2, pid: 20, appWindows: [2]))
}
@Test func ownOverlayDoesNotOcclude() {
    let overlay = w(6, me, CGRect(x: 0, y: 0, width: 1000, height: 1000), layer: 1000)
    let s = WindowStack([overlay, b])
    #expect(s.isVisible(CGPoint(x: 80, y: 30), window: 2, pid: 20, appWindows: [2]))
}

@Test func appsToScanAreUniqueFrontToBackWithoutJumpr() {
    let settings = w(5, me, CGRect(x: 60, y: 10, width: 40, height: 40))
    let b2 = w(11, 20, CGRect(x: 0, y: 0, width: 10, height: 10))
    let s = WindowStack([settings, b, a, b2])
    #expect(s.appsToScan(excluding: me, front: 20) == [20, 10])
}
@Test func frontAppWithoutWindowsIsStillScanned() {   // its menu bar
    let s = WindowStack([a, b])
    #expect(s.appsToScan(excluding: me, front: 40) == [10, 20, 40])
    #expect(s.appsToScan(excluding: me, front: me) == [10, 20])
    #expect(s.appsToScan(excluding: me, front: nil) == [10, 20])
}

@Test func appsWithVisibleWindowSkipJumprHiddenAndNonNormalLayers() {
    let settings = w(5, me, CGRect(x: 0, y: 0, width: 400, height: 400))
    let panel = w(12, 50, CGRect(x: 500, y: 0, width: 50, height: 50), layer: 3)
    let c = w(13, 60, CGRect(x: 700, y: 0, width: 50, height: 50))
    // a and b are fully under Jumpr's Settings window; c is visible; 50 has only a panel.
    #expect(WindowStack([settings, a, b, panel, c]).appsWithVisibleWindow(excluding: me) == [60])
    #expect(WindowStack([a, b, c]).appsWithVisibleWindow(excluding: me) == [10, 20, 60])
}

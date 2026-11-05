import Testing
import CoreGraphics
@testable import JumprCore

// This Mac's real layout (AppKit frames, bottom-left origin at the primary's bottom-left).
private let primaryHeight: CGFloat = 1440
private let primaryAppKit = CGRect(x: 0, y: 0, width: 3440, height: 1440)
private let leftAppKit = CGRect(x: -1920, y: 122, width: 1920, height: 1080)    // 1440 - (238 + 1080)
private let belowAppKit = CGRect(x: 0, y: -1080, width: 1920, height: 1080)    // 1440 - (1440 + 1080)

@Test func primaryDisplayGlobalFrame() {
    #expect(displayFrameTopLeft(appKit: primaryAppKit, primaryHeight: primaryHeight)
            == CGRect(x: 0, y: 0, width: 3440, height: 1440))
}

@Test func leftDisplayGlobalFrame() {
    #expect(displayFrameTopLeft(appKit: leftAppKit, primaryHeight: primaryHeight)
            == CGRect(x: -1920, y: 238, width: 1920, height: 1080))
}

@Test func belowDisplayGlobalFrame() {
    #expect(displayFrameTopLeft(appKit: belowAppKit, primaryHeight: primaryHeight)
            == CGRect(x: 0, y: 1440, width: 1920, height: 1080))
}

@Test func primaryCornerLabelsMapToLocalRects() {
    let d = displayFrameTopLeft(appKit: primaryAppKit, primaryHeight: primaryHeight)
    // Top-left corner: high in the bottom-left local space.
    #expect(overlayLocalRect(CGRect(x: 2, y: 2, width: 30, height: 20), display: d)
            == CGRect(x: 2, y: 1418, width: 30, height: 20))
    // Bottom-right corner: near local y 0.
    #expect(overlayLocalRect(CGRect(x: 3400, y: 1400, width: 30, height: 20), display: d)
            == CGRect(x: 3400, y: 20, width: 30, height: 20))
}

@Test func leftDisplayCornerLabelMapsToLocalRect() {
    let d = displayFrameTopLeft(appKit: leftAppKit, primaryHeight: primaryHeight)
    // Top-left corner of the left display, with a fractional origin (rounded, size kept).
    #expect(overlayLocalRect(CGRect(x: -1917.6, y: 240, width: 30.5, height: 20), display: d)
            == CGRect(x: 2, y: 1058, width: 30.5, height: 20))
}

@Test func belowDisplayCornerLabelMapsToLocalRect() {
    let d = displayFrameTopLeft(appKit: belowAppKit, primaryHeight: primaryHeight)
    // Bottom-right corner of the display below the primary.
    #expect(overlayLocalRect(CGRect(x: 1880, y: 2500, width: 30, height: 20), display: d)
            == CGRect(x: 1880, y: 0, width: 30, height: 20))
}

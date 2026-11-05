import CoreGraphics

/// A display's frame in global top-left coordinates, from its AppKit (bottom-left) frame.
/// `primaryHeight` is the height of the primary display, whose top-left is the origin of both.
public func displayFrameTopLeft(appKit f: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
}

/// A global top-left rect → the overlay window's bottom-left layer space on the display
/// whose global top-left frame is `display`. The origin is rounded to whole points.
public func overlayLocalRect(_ r: CGRect, display: CGRect) -> CGRect {
    CGRect(x: (r.minX - display.minX).rounded(),
           y: (display.height - (r.minY - display.minY) - r.height).rounded(),
           width: r.width, height: r.height)
}

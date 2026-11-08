import AppKit
import JumprCore

/// Label look, re-read from user defaults on every trigger so changes apply without a relaunch.
/// The two colours also change while labels are up (`Controller.recolor`); the size does not.
struct LabelStyle {
    let font: NSFont
    let size: CGFloat
    let advance: CGFloat
    var bg: CGColor
    var fg: CGColor

    static func current() -> LabelStyle {
        let d = UserDefaults.standard
        let size = CGFloat(clampLabelSize(d.double(forKey: Keys.labelSize)))
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let bg = storedLabelColor()
        let fg = storedLetters().color(on: bg)
        func cg(_ c: RGB) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }  // sRGB, as in the panel's preview
        return LabelStyle(font: font, size: size, advance: font.maximumAdvancement.width, bg: cg(bg), fg: cg(fg))
    }
}

/// The label colour from user defaults, or the default yellow.
func storedLabelColor() -> RGB {
    UserDefaults.standard.string(forKey: Keys.labelColor).flatMap { RGB(hex: $0) } ?? RGB(hex: "FFD60A")!
}

/// The letter colour setting from user defaults.
func storedLetters() -> Letters {
    let d = UserDefaults.standard
    return Letters(storedMode: d.string(forKey: Keys.labelTextMode), storedTextColor: d.string(forKey: Keys.labelTextColor))
}

/// One transparent, click-through window per display, always ordered in, so showing
/// labels is just adding layers. Takes global top-left rects; the flip to AppKit's
/// bottom-left happens only here.
final class Overlay {
    /// This display in global top-left coordinates.
    let frame: CGRect

    private let window: NSWindow
    private let root = CALayer()
    private let scale: CGFloat

    init(_ screen: NSScreen, primaryHeight: CGFloat) {
        let f = screen.frame
        frame = displayFrameTopLeft(appKit: f, primaryHeight: primaryHeight)
        scale = screen.backingScaleFactor
        window = NSWindow(contentRect: f, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none  // no open animation: the window is exactly the display
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let v = NSView(frame: CGRect(origin: .zero, size: f.size))
        v.layer = root
        v.wantsLayer = true
        window.contentView = v
        window.setFrame(f, display: true)
        window.orderFrontRegardless()
    }

    /// Layers currently on this overlay (labels and the readout panel).
    var layerCount: Int { root.sublayers?.count ?? 0 }

    /// `rect` is the label's own frame in global top-left coordinates (see `Labels.frame`).
    func add(label: String, at rect: CGRect, style: LabelStyle) -> CALayer {
        let l = CATextLayer()
        l.string = label
        l.font = style.font
        l.fontSize = style.size
        l.alignmentMode = .center
        l.foregroundColor = style.fg
        l.backgroundColor = style.bg
        l.cornerRadius = style.size / 4
        l.borderWidth = 0.5
        l.borderColor = CGColor(gray: 0, alpha: 0.6)
        add(layer: l, at: rect)
        return l
    }

    /// Scroll mode's outline around `area` (global top-left): 2 pt in the label colour
    /// between two thin dark edges, so it reads on light and dark content alike, and the
    /// SCROLL tag at `tag`, in the label's colours.
    func add(outline area: CGRect, tag: CGRect, tagFont: NSFont, style: LabelStyle) -> CALayer {
        let dark = CGColor(gray: 0, alpha: 0.6)
        let outer = CALayer()
        outer.borderWidth = 0.5
        outer.borderColor = dark
        let band = CALayer()
        band.frame = CGRect(origin: .zero, size: area.size).insetBy(dx: 0.5, dy: 0.5)
        band.borderWidth = 2
        band.borderColor = style.bg
        let inner = CALayer()
        inner.frame = band.bounds.insetBy(dx: 2, dy: 2)
        inner.borderWidth = 0.5
        inner.borderColor = dark
        band.addSublayer(inner)
        outer.addSublayer(band)

        let t = CATextLayer()
        t.string = "SCROLL"
        t.font = tagFont
        t.fontSize = tagFont.pointSize
        t.alignmentMode = .center
        t.foregroundColor = style.fg
        t.backgroundColor = style.bg
        t.cornerRadius = tagFont.pointSize / 4
        t.borderWidth = 0.5
        t.borderColor = dark
        // The tag is a sublayer, placed in the outline's own (bottom-left) space.
        t.frame = CGRect(x: tag.minX - area.minX, y: area.maxY - tag.maxY, width: tag.width, height: tag.height)
        t.contentsScale = scale
        outer.addSublayer(t)
        [band, inner].forEach { $0.contentsScale = scale }
        add(layer: outer, at: area)
        return outer
    }

    /// Adds any layer (e.g. the readout panel) at a global top-left rect.
    func add(layer: CALayer, at rect: CGRect) {
        layer.contentsScale = scale
        quietly {
            layer.frame = local(rect)
            root.addSublayer(layer)
        }
    }

    func clear() {
        quietly { root.sublayers?.forEach { $0.removeFromSuperlayer() } }
    }

    func close() {
        clear()
        window.close()
    }

    /// Global top-left → this window's bottom-left layer space.
    private func local(_ r: CGRect) -> CGRect {
        overlayLocalRect(r, display: frame)
    }

    private func quietly(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}

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
        func color(_ key: String, _ fallback: String) -> CGColor {
            let c = d.string(forKey: key).flatMap { RGB(hex: $0) } ?? RGB(hex: fallback)!
            return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)  // sRGB, as in the Settings preview
        }
        return LabelStyle(font: font, size: size, advance: font.maximumAdvancement.width,
                          bg: color(Keys.labelColor, "FFD60A"), fg: color(Keys.labelTextColor, "000000"))
    }
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

    /// Adds any layer (e.g. the readout panel) at a global top-left rect.
    func add(layer: CALayer, at rect: CGRect) {
        layer.contentsScale = scale
        quietly {
            layer.frame = local(rect)
            root.addSublayer(layer)
        }
    }

    func remove(_ layer: CALayer) {
        quietly { layer.removeFromSuperlayer() }
    }

    func move(_ layer: CALayer, to rect: CGRect) {
        quietly { layer.frame = local(rect) }
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

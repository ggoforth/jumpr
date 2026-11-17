import AppKit

/// The menu bar icon and the panel it opens. A click shows the panel under the icon; a
/// second click, or a click anywhere else, closes it.
final class StatusItem: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let plainImage: NSImage? = StatusItem.letterImage()
    private let heldImage: NSImage? = StatusItem.letterImage(knockedOut: true)
    private var updatePending = false
    private lazy var badgedImage = plainImage.map(Self.badged)
    /// Called just before the panel shows, to refresh state that can change outside Jumpr.
    var willShow: () -> Void = {}

    /// The menu bar icon: the J from the site's logo and from Jumpr's own labels (the bold
    /// monospaced system font), with no box. Template, so the menu bar draws it white on a
    /// dark bar and black on a light one.
    ///
    /// `knockedOut` is the held icon: a filled rounded rectangle with the J cut out of it
    /// (smaller, to sit inside the box), so it reads like the highlight the system used to
    /// draw. See `holdsHighlight` for why it is drawn here.
    private static func letterImage(knockedOut: Bool = false) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: knockedOut ? 14 : 17, weight: .bold)
        let letter = NSAttributedString(string: "J", attributes: [.font: font, .foregroundColor: NSColor.black])
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let size = letter.size()
            if knockedOut {
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            }
            letter.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jumpr"
        return image
    }

    /// Set once at launch; the panel's own buttons call back into this item to close it.
    var panel: NSViewController? {
        get { popover.contentViewController }
        set { popover.contentViewController = newValue }
    }

    override init() {
        super.init()
        updateImage()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc private func toggle() {
        popover.isShown ? closePanel() : showPanel()
    }

    func showPanel() {
        guard let button = item.button, panel != nil, !popover.isShown else { return }
        willShow()
        // Jumpr is rarely the active app; without activating, the panel could not take the
        // keys the "Exact color" field and the shortcut recorder need.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
        // Again on the next turn: when a click opened the panel, the button drops its
        // highlight as that click ends. The highlight is what accessibility reports as
        // "selected", and a scan looks inside a menu bar item only while it is selected, so
        // without this the open panel's controls got no labels.
        DispatchQueue.main.async { [weak self] in
            guard let self, popover.isShown else { return }
            item.button?.highlight(true)
        }
    }

    func closePanel() {
        popover.performClose(nil)
    }

    /// A click on the icon itself is left to `toggle`: if the popover closed itself on that
    /// mouse down, the same click would open it again at once.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
              let button = item.button, event.window === button.window else { return true }
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(holdsHighlight)
    }

    /// Marks that Jumpr has the keys (scroll mode, persistent mode): the icon is drawn filled
    /// with the J knocked out, as the open panel's highlight used to look. The button is still
    /// highlighted too, because accessibility reports that as "selected" (see `showPanel`).
    /// macOS 27 keeps that highlight state but no longer draws it: measured on 26A428,
    /// `isHighlighted` stays true while a capture of the icon is byte-identical, and
    /// `state = .on` is not drawn either. Swapping the image is drawn.
    var holdsHighlight = false {
        didSet {
            item.button?.highlight(holdsHighlight || popover.isShown)
            updateImage()
        }
    }

    /// A gentle reminder for a scheduled update Sparkle did not bring forward: a dot on the
    /// menu bar icon (the panel shows its own banner). Not shown while the icon is held; it
    /// comes back when the hold ends.
    func setUpdatePending(_ pending: Bool) {
        updatePending = pending
        updateImage()
    }

    /// The one place the icon's image is chosen: held, else update pending, else plain.
    private func updateImage() {
        item.button?.image = holdsHighlight ? heldImage : updatePending ? badgedImage : plainImage
    }

    /// The icon with a dot at its top right, cut out from the glyph so it reads at menu bar
    /// size. Template, so the menu bar draws it for light and dark like the plain icon.
    private static func badged(_ base: NSImage) -> NSImage {
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let d = rect.width * 0.42
            let dot = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jumpr, update available"
        return image
    }
}

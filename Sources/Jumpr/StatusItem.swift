import AppKit

final class StatusItem: NSObject, NSMenuItemValidation {
    var onSettings: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var canCheckForUpdates: () -> Bool = { false }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let plainImage: NSImage? = StatusItem.letterImage()
    private lazy var badgedImage = plainImage.map(Self.badged)

    /// The menu bar icon: the J from the site's logo and from Jumpr's own labels (the bold
    /// monospaced system font), with no box. Template, so the menu bar draws it white on a
    /// dark bar and black on a light one.
    private static func letterImage() -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: 17, weight: .bold)
        let letter = NSAttributedString(string: "J", attributes: [.font: font, .foregroundColor: NSColor.black])
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let size = letter.size()
            letter.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jumpr"
        return image
    }

    override init() {
        super.init()
        item.button?.image = plainImage

        let menu = NSMenu()
        // "Jumpr 1.0.0", shown greyed out: it has no action, so the menu disables it.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        menu.addItem(NSMenuItem(title: "Jumpr \(version)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        pauseItem.target = self
        updatesItem.target = self
        menu.addItem(settings)
        menu.addItem(pauseItem)
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jumpr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func setPaused(_ paused: Bool) {
        pauseItem.title = paused ? "Resume" : "Pause"
    }

    /// A gentle reminder for a scheduled update Sparkle did not bring forward: a dot on the
    /// menu bar icon and "Update Available…" in place of "Check for Updates…".
    func setUpdatePending(_ pending: Bool) {
        item.button?.image = pending ? badgedImage : plainImage
        updatesItem.title = pending ? "Update Available…" : "Check for Updates…"
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

    @objc private func openSettings() { onSettings() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func checkForUpdates() { onCheckForUpdates() }

    /// Asked each time the menu opens: "Check for Updates…" only while Sparkle can check.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem === updatesItem ? canCheckForUpdates() : true
    }
}

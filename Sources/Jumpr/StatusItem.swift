import AppKit

final class StatusItem: NSObject, NSMenuItemValidation {
    var onSettings: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var canCheckForUpdates: () -> Bool = { false }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "Jumpr")

        let menu = NSMenu()
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

    @objc private func openSettings() { onSettings() }
    @objc private func togglePause() { onTogglePause() }
    @objc private func checkForUpdates() { onCheckForUpdates() }

    /// Asked each time the menu opens: "Check for Updates…" only while Sparkle can check.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem === updatesItem ? canCheckForUpdates() : true
    }
}

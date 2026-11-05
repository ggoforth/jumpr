import AppKit

final class StatusItem: NSObject {
    var onSettings: () -> Void = {}
    var onTogglePause: () -> Void = {}

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "Jumpr")

        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        pauseItem.target = self
        menu.addItem(settings)
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jumpr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func setPaused(_ paused: Bool) {
        pauseItem.title = paused ? "Resume" : "Pause"
    }

    @objc private func openSettings() { onSettings() }
    @objc private func togglePause() { onTogglePause() }
}

import AppKit
import JumprCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = StatusItem()
let scanner = Scanner()
let treeRegistry = TreeRegistry()
log("launch")
log("trusted: \(AXIsProcessTrusted())")

/// Each display's frame in global top-left coordinates.
func globalScreens() -> [CGRect] {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSScreen.screens.map { s in
        CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
    }
}

/// Debug: cold scan of every on-screen app, logged. No painting.
func debugColdScan() {
    let t0 = now()
    let stack = WindowServer.snapshot()
    let screens = globalScreens()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier

    var pids: [Int32] = []
    var names: [Int32: String] = [:]
    for w in stack.wins where names[w.pid] == nil {
        pids.append(w.pid)
        names[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? w.name
    }

    struct Tally { var ms = 0.0, nodes = 0, windowNodes = 0, labels = 0, timedOut = false }
    var tallies: [Int32: Tally] = [:]
    var remaining = pids.count

    func finish() {
        let labels = tallies.values.reduce(0) { $0 + $1.labels }
        var lines = [String(format: "scan total=%.0f labels=%d apps=%d", (now() - t0) * 1000, labels, pids.count)]
        for pid in pids.sorted(by: { tallies[$0]!.ms > tallies[$1]!.ms }) {
            let t = tallies[pid]!
            lines.append(String(format: "  %.0f ms %d nodes %d labels ", t.ms, t.nodes, t.labels)
                + (names[pid] ?? "?") + (t.timedOut ? " TIMEOUT" : ""))
        }
        log(lines.joined(separator: "\n"))
    }

    if pids.isEmpty { finish(); return }
    for pid in pids {
        tallies[pid] = Tally()
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let isDock = bundle == "com.apple.dock"
        let hasVisibleWindow = stack.wins.contains { $0.pid == pid && $0.layer == 0 && stack.anyVisible($0.id) }
        if hasVisibleWindow && !isDock {
            scanner.perform(pid: pid, background: false) { treeRegistry.enableIfNeeded(pid: pid, bundleID: bundle) }
        }
        scanner.scanApp(pid: pid, stack: stack, screens: screens, frontPid: front, isDock: isDock, background: false,
                        each: { s in
                            tallies[pid]!.nodes += s.nodes
                            tallies[pid]!.labels += s.targets.count
                            tallies[pid]!.timedOut = tallies[pid]!.timedOut || s.timedOut
                            if s.window != nil { tallies[pid]!.windowNodes += s.nodes }
                        },
                        done: {
                            tallies[pid]!.ms = (now() - t0) * 1000
                            if hasVisibleWindow {
                                let windowNodes = tallies[pid]!.windowNodes
                                scanner.perform(pid: pid, background: true) {
                                    treeRegistry.noteScan(pid: pid, bundleID: bundle, windowNodes: windowNodes)
                                }
                            }
                            remaining -= 1
                            if remaining == 0 { finish() }
                        })
    }
}

signal(SIGUSR1, SIG_IGN)
let debugSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
debugSignal.setEventHandler { debugColdScan() }
debugSignal.resume()

app.run()

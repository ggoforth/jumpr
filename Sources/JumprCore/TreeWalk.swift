import CoreGraphics

public struct ElementID: Hashable {
    public let raw: AnyHashable

    public init(_ raw: AnyHashable) {
        self.raw = raw
    }
}

public struct NodeInfo {
    public var role: String
    public var frame: CGRect?
    public var enabled: Bool?
    public var children: [any AXNode]

    public init(role: String, frame: CGRect?, enabled: Bool?, children: [any AXNode]) {
        self.role = role
        self.frame = frame
        self.enabled = enabled
        self.children = children
    }
}

public protocol AXNode {
    var id: ElementID { get }
    func info() -> NodeInfo?
    func isSelected() -> Bool
    func visibleRows() -> [any AXNode]?
}

public struct Target: Equatable {
    public let id: ElementID
    public let rect: CGRect
    public let role: String
    public let pid: Int32
    public let window: WindowID?
    /// Inside web content (under an `AXWebArea`): a browser page or an Electron app's UI.
    public let inWeb: Bool

    public init(id: ElementID, rect: CGRect, role: String, pid: Int32, window: WindowID?, inWeb: Bool = false) {
        self.id = id
        self.rect = rect
        self.role = role
        self.pid = pid
        self.window = window
        self.inWeb = inWeb
    }
}

public enum Roles {
    public static let text: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    public static let leaf: Set<String> = text.union([
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXDisclosureTriangle", "AXSlider", "AXIncrementor", "AXColorWell", "AXDockItem",
    ])
    public static let clickable: Set<String> = leaf.union(["AXMenuItem", "AXMenuBarItem", "AXRow"])
}

public enum WalkScope {
    case window(id: WindowID, bounds: CGRect, appWindows: Set<WindowID>)
    case system(screens: [CGRect])
}

public struct WalkResult {
    public var targets: [Target]
    public var nodes: Int
    public var timedOut: Bool
    /// `AXWebArea` nodes visited, empty ones included (see `webViewMayStillBeBuilding`).
    public var webAreas = 0

    public init(targets: [Target], nodes: Int, timedOut: Bool) {
        self.targets = targets
        self.nodes = nodes
        self.timedOut = timedOut
    }
}

private let maxDepth = 80

public func walk(root: any AXNode, pid: Int32, scope: WalkScope, stack: WindowStack,
                 deadline: Double, now: () -> Double) -> WalkResult {
    var result = WalkResult(targets: [], nodes: 0, timedOut: false)
    let startClip: CGRect
    switch scope {
    case .window(_, let bounds, _): startClip = bounds
    case .system: startClip = .infinite
    }

    func visit(_ node: any AXNode, clip: CGRect, depth: Int, inWeb: Bool) {
        if depth >= maxDepth || result.timedOut { return }
        if now() > deadline {
            result.timedOut = true
            return
        }
        result.nodes += 1
        guard let info = node.info() else { return }
        if info.role == "AXColumn" { return }
        if info.role == "AXWebArea" { result.webAreas += 1 }
        let inWeb = inWeb || info.role == "AXWebArea"

        var clip = clip
        var visibleRect: CGRect?
        if let f = info.frame, f.width > 0, f.height > 0 {
            let r = f.intersection(clip)
            if r.isEmpty { return }
            visibleRect = r
            if info.role == "AXScrollArea" { clip = r }
        }

        if Roles.clickable.contains(info.role), info.enabled != false,
           let r = visibleRect, r.width >= 4, r.height >= 4 {
            let c = CGPoint(x: r.midX, y: r.midY)
            switch scope {
            case .window(let id, _, let appWindows):
                if stack.isVisible(c, window: id, pid: pid, appWindows: appWindows) {
                    result.targets.append(Target(id: node.id, rect: r, role: info.role, pid: pid, window: id, inWeb: inWeb))
                }
            case .system(let screens):
                if screens.contains(where: { $0.contains(c) }) {
                    result.targets.append(Target(id: node.id, rect: r, role: info.role, pid: pid, window: nil, inWeb: inWeb))
                }
            }
        }

        if Roles.leaf.contains(info.role) { return }
        if (info.role == "AXMenuBarItem" || info.role == "AXMenuItem") && !node.isSelected() { return }

        var children = info.children
        if info.role == "AXTable" || info.role == "AXOutline",
           let rows = node.visibleRows(), !rows.isEmpty {
            children = rows
        }
        for child in children {
            visit(child, clip: clip, depth: depth + 1, inWeb: inWeb)
        }
    }

    visit(root, clip: startClip, depth: 0, inWeb: false)
    return result
}

/// Whether a web tree switched on `sinceSwitchedOn` seconds ago may still be arriving, so a
/// scan of its app is worth repeating. Web apps build the tree some time after being asked:
/// 1Password answered with empty containers at 0.5 s and the full tree by 2 s; Chrome's
/// page was still missing at 1.7 s and there at 2.1 s.
/// `nil`: Jumpr never switched this app's tree on (a native app, or one that refused).
public func treeMayStillBeBuilding(sinceSwitchedOn: Double?, allow: Double = 3.0) -> Bool {
    guard let sinceSwitchedOn else { return false }
    return sinceSwitchedOn < allow
}

/// Whether a web view may still be building its tree, so a scan of its app is worth
/// repeating. A WebKit view builds its tree only once something has asked for it: the first
/// scan of an email open in Mail found no links, the next found ten.
/// `hostsWeb`: the app has shown a web area, in this scan or an earlier one.
/// `webTargets`: what this scan found to click inside web areas.
/// `sinceTrigger`: seconds since the labels went up.
public func webViewMayStillBeBuilding(hostsWeb: Bool, webTargets: Int, sinceTrigger: Double,
                                      allow: Double = 1.3) -> Bool {
    hostsWeb && webTargets == 0 && sinceTrigger < allow
}

/// Whether a web browser's page is missing from its tree: a window was walked and there
/// was nothing to click inside web content. An empty window is not the sign: Chrome with
/// its page tree off still answers with its toolbar (about 60 nodes).
/// Undecided (false) when no window was walked.
public func webTreeLooksEmpty(walkedWindow: Bool, webTargets: Int) -> Bool {
    walkedWindow && webTargets == 0
}

/// Whether a browser whose page looks missing may be sent the heavier
/// `AXEnhancedUserInterface` on this scan (`scan` counts from 1). One that accepted
/// `AXManualAccessibility` may still be building that tree on its first scan, so wait for
/// the second. One that refused it (Chrome) has nothing to wait for.
public func mayAskForEnhancedTree(scan: Int, manualAccepted: Bool) -> Bool {
    scan >= 2 || !manualAccepted
}

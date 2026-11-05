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

    public init(id: ElementID, rect: CGRect, role: String, pid: Int32, window: WindowID?) {
        self.id = id
        self.rect = rect
        self.role = role
        self.pid = pid
        self.window = window
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

    func visit(_ node: any AXNode, clip: CGRect, depth: Int) {
        if depth >= maxDepth || result.timedOut { return }
        if now() > deadline {
            result.timedOut = true
            return
        }
        result.nodes += 1
        guard let info = node.info() else { return }
        if info.role == "AXColumn" { return }

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
                    result.targets.append(Target(id: node.id, rect: r, role: info.role, pid: pid, window: id))
                }
            case .system(let screens):
                if screens.contains(where: { $0.contains(c) }) {
                    result.targets.append(Target(id: node.id, rect: r, role: info.role, pid: pid, window: nil))
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
            visit(child, clip: clip, depth: depth + 1)
        }
    }

    visit(root, clip: startClip, depth: 0)
    return result
}

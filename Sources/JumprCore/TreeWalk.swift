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
    /// The element itself can take keyboard focus (it is its own `AXFocusableAncestor`).
    /// Web content only: other apps do not have the attribute.
    public var focusable: Bool

    public init(role: String, frame: CGRect?, enabled: Bool?, children: [any AXNode], focusable: Bool = false) {
        self.role = role
        self.frame = frame
        self.enabled = enabled
        self.children = children
        self.focusable = focusable
    }
}

public protocol AXNode {
    var id: ElementID { get }
    func info() -> NodeInfo?
    func isSelected() -> Bool
    func visibleRows() -> [any AXNode]?
    /// Whether the element offers `AXPress`. One more request, so `walk` asks sparingly.
    func offersPress() -> Bool
    /// Whether the element offers `AXScrollUpByPage` or `AXScrollDownByPage`. One more
    /// request, asked only of large groups outside web content and outside any area found.
    func offersPageScroll() -> Bool
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

/// Somewhere scroll mode can scroll: a scroll area, a page, or a scrolling region of web
/// content. Its rectangle is the visible part, global top-left.
public struct Area: Equatable {
    public let id: ElementID
    public let rect: CGRect
    public let pid: Int32
    public let window: WindowID
    /// A point of the area that is on top, where a wheel event reaches it: its center, or
    /// when another window covers that, a point that shows.
    public let aim: CGPoint
    /// Where its letter goes: its top-left corner, or `aim` when that corner is covered.
    public let anchor: CGPoint

    public init(id: ElementID, rect: CGRect, pid: Int32, window: WindowID, aim: CGPoint? = nil, anchor: CGPoint? = nil) {
        self.id = id
        self.rect = rect
        self.pid = pid
        self.window = window
        self.aim = aim ?? CGPoint(x: rect.midX, y: rect.midY)
        self.anchor = anchor ?? rect.origin
    }
}

/// What a walk collects: targets to label, or areas to scroll.
public enum Finding {
    case targets, areas
}

public enum Roles {
    public static let text: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    public static let leaf: Set<String> = text.union([
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXDisclosureTriangle", "AXSlider", "AXIncrementor", "AXColorWell", "AXDockItem",
    ])
    public static let clickable: Set<String> = leaf.union(["AXMenuItem", "AXMenuBarItem", "AXRow"])
    /// Clickable only if the element itself offers `AXPress`. Apps built with the iPad
    /// frameworks present a list item as text: every conversation and pin in Messages'
    /// sidebar is an `AXStaticText` that offers a press. Text only: there, plain groups
    /// offer a press too.
    public static let clickableIfPressable: Set<String> = ["AXStaticText"]
    /// Clickable in web content only if the element itself can take keyboard focus. A page
    /// builds controls out of plain text: each day in a date picker is an `AXStaticText`
    /// with no press action, and being focusable is what sets it apart from the text
    /// around it. Text only: scrolling regions, splitters and toolbars take focus too.
    public static let clickableIfFocusable: Set<String> = ["AXStaticText"]
    /// Clickable only as a list's own item (a direct child of an `AXList`). Dia's sidebar
    /// presents each folder as an `AXUnknown` child of its list, with no children and no
    /// actions: its place in the list is the only sign that it is something to click.
    public static let clickableAsListItem: Set<String> = ["AXUnknown"]
    /// Areas to scroll: a scroll area, a page.
    public static let scrollable: Set<String> = ["AXScrollArea", "AXWebArea"]
    /// Areas to scroll in web content only, if the element itself can take keyboard focus.
    /// Chromium and Electron expose a scrolling region as a plain group with no scroll role;
    /// being focusable is what sets it apart from the groups around it.
    public static let scrollableIfFocusable: Set<String> = ["AXGroup"]
    /// Areas to scroll outside web content, if the element itself offers the page-scroll
    /// actions. Apps built with the iPad frameworks present a scrolling pane as a plain
    /// group: both panes in Messages are such groups.
    public static let scrollableIfPagesByAction: Set<String> = ["AXGroup"]
}

/// The smallest area worth scrolling, per side of its visible part. Smaller ones are a
/// toolbar's strip or a row of tags, not something a person reads by scrolling.
public let minAreaSide: CGFloat = 80

/// Whether two nested areas are one to a person: every edge within 6 pt. Safari wraps its
/// page in a scroll area of the same size.
public func nearlySameRect(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) <= 6 && abs(a.maxX - b.maxX) <= 6
        && abs(a.minY - b.minY) <= 6 && abs(a.maxY - b.maxY) <= 6
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
    /// Areas to scroll, when the walk looks for them (`Finding.areas`).
    public var areas: [Area] = []

    public init(targets: [Target], nodes: Int, timedOut: Bool) {
        self.targets = targets
        self.nodes = nodes
        self.timedOut = timedOut
    }
}

private let maxDepth = 80

/// `finding`: targets to label, or areas to scroll. Both share the clip, the on-top rule and
/// the descent. Looking for areas labels nothing and never asks whether text offers a press;
/// areas are found in windows only, never in the menu bar or the Dock.
public func walk(root: any AXNode, pid: Int32, scope: WalkScope, stack: WindowStack,
                 deadline: Double, now: () -> Double, finding: Finding = .targets) -> WalkResult {
    var result = WalkResult(targets: [], nodes: 0, timedOut: false)
    let startClip: CGRect
    switch scope {
    case .window(_, let bounds, _): startClip = bounds
    case .system: startClip = .infinite
    }

    /// Records the node as an area if it is one, and returns the nearest area around its
    /// children. Kept out of `visit`, whose frame is on the stack once per level of the tree.
    func noteArea(_ node: any AXNode, role: String, focusable: Bool, frame: CGRect, visible r: CGRect, inWeb: Bool,
                  inArea: Int?) -> Int? {
        guard case .window(let window, _, let appWindows) = scope,
              r.width >= minAreaSide, r.height >= minAreaSide,
              Roles.scrollable.contains(role) || (inWeb && focusable && Roles.scrollableIfFocusable.contains(role))
                || (!inWeb && inArea == nil && Roles.scrollableIfPagesByAction.contains(role) && node.offersPageScroll())
        else { return inArea }
        let onTop = { (p: CGPoint) in stack.isVisible(p, window: window, pid: pid, appWindows: appWindows) }
        // A wheel event reaches the area only at a point that shows. The center first; when
        // another window covers it (a browser with a chat window over its middle), a point
        // from a 5×5 grid that shows; none, and there is nothing to aim at.
        guard let aim = visiblePoint(in: r, onTop: onTop) else { return inArea }
        // One that runs past the area around it is that area's content, scrolled by it, not
        // an area of its own: Mail's message body sits in the pane that scrolls the header
        // and the body together.
        if let outer = inArea, !result.areas[outer].rect.insetBy(dx: -6, dy: -6).contains(frame) { return outer }
        let corner = CGPoint(x: r.minX + 12, y: r.minY + 12)
        let area = Area(id: node.id, rect: r, pid: pid, window: window, aim: aim, anchor: onTop(corner) ? r.origin : aim)
        // Nested areas of one size are one area to a person: keep the innermost, the one
        // that holds the content.
        if let outer = inArea, nearlySameRect(result.areas[outer].rect, r) {
            result.areas[outer] = area
            return outer
        }
        result.areas.append(area)
        return result.areas.count - 1
    }

    /// `inTarget`: under an element that got a label. `inList`: a list's own item.
    /// `inArea`: the index in `result.areas` of the nearest area around this node.
    func visit(_ node: any AXNode, clip: CGRect, depth: Int, inWeb: Bool, inTarget: Bool, inList: Bool,
               inArea: Int?) {
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

        var inArea = inArea
        if finding == .areas, let r = visibleRect {
            inArea = noteArea(node, role: info.role, focusable: info.focusable, frame: info.frame ?? r, visible: r,
                              inWeb: inWeb, inArea: inArea)
        }

        let before = result.targets.count
        // Asking whether text offers a press is one more request per element, so it comes
        // last and is skipped where the answer cannot matter: in web content (a long page
        // holds thousands of text nodes, and its links and buttons have roles of their own)
        // and under an element that already has a label (the text in a table's rows).
        if finding == .targets, info.enabled != false, let r = visibleRect, r.width >= 4, r.height >= 4,
           Roles.clickable.contains(info.role)
            || (inList && Roles.clickableAsListItem.contains(info.role))
            || (inWeb && info.focusable && Roles.clickableIfFocusable.contains(info.role))
            || (Roles.clickableIfPressable.contains(info.role) && !inWeb && !inTarget && node.offersPress()) {
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
        let mine: Int? = result.targets.count > before ? before : nil

        if Roles.leaf.contains(info.role) { return }
        if (info.role == "AXMenuBarItem" || info.role == "AXMenuItem") && !node.isSelected() { return }

        var children = info.children
        if info.role == "AXTable" || info.role == "AXOutline",
           let rows = node.visibleRows(), !rows.isEmpty {
            children = rows
        }
        // A page's lists hold links, which have a role of their own, so only lists outside
        // web content count.
        let isList = info.role == "AXList" && !inWeb
        let firstInList = result.targets.count
        for child in children {
            visit(child, clip: clip, depth: depth + 1, inWeb: inWeb, inTarget: inTarget || mine != nil, inList: isList,
                  inArea: inArea)
        }

        // An item with no role can span more than its own line: an open folder in Dia also
        // spans the tabs in it, which are the list's next items. Its label and its click
        // belong on the part the list's other labels leave free; with nothing free, it gets
        // none. In list order, so an outer item is trimmed before the items inside it.
        if isList {
            var i = firstInList
            while i < result.targets.count {
                let t = result.targets[i]
                guard Roles.clickableAsListItem.contains(t.role) else { i += 1; continue }
                let others = result.targets[firstInList...].filter { $0.id != t.id }.map(\.rect)
                if let free = largestFreeBand(of: t.rect, around: others) {
                    result.targets[i] = Target(id: t.id, rect: free, role: t.role, pid: t.pid, window: t.window, inWeb: t.inWeb)
                    i += 1
                } else {
                    result.targets.remove(at: i)
                }
            }
        }

        // A clickable element (a row) with a clickable element inside it that covers at
        // least half its area gets no label of its own: both labels would sit at the same
        // right end (`Labels.frame`), and a press on the row mostly lands on the inner one
        // anyway. A smaller control inside (a checkbox at the edge of a wide row) is a
        // different action, so both keep their labels.
        if let mine {
            let outer = result.targets[mine].rect
            if result.targets[(mine + 1)...].contains(where: { coversHalf($0.rect, of: outer) }) {
                result.targets.remove(at: mine)
            }
        }
    }

    visit(root, clip: startClip, depth: 0, inWeb: false, inTarget: false, inList: false, inArea: nil)
    return result
}

/// The largest part of `rect` beside everything in `others` that overlaps it: the band
/// above, below, left or right of what they cover together. `rect` itself if nothing
/// overlaps it; nil if no band of at least 4×4 pt is left.
func largestFreeBand(of rect: CGRect, around others: [CGRect]) -> CGRect? {
    var covered = CGRect.null
    for other in others {
        let overlap = other.intersection(rect)
        if !overlap.isEmpty { covered = covered.union(overlap) }   // null and edge-touching are empty
    }
    if covered.isNull { return rect }
    let bands = [
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: covered.minY - rect.minY),
        CGRect(x: rect.minX, y: covered.maxY, width: rect.width, height: rect.maxY - covered.maxY),
        CGRect(x: rect.minX, y: rect.minY, width: covered.minX - rect.minX, height: rect.height),
        CGRect(x: covered.maxX, y: rect.minY, width: rect.maxX - covered.maxX, height: rect.height),
    ].filter { $0.width >= 4 && $0.height >= 4 }
    return bands.max { $0.width * $0.height < $1.width * $1.height }
}

/// A point of `rect` for which `onTop` is true: its center, else the first of a 5×5 grid
/// inside it (the same grid `WindowStack.anyVisible` samples); nil when none is.
func visiblePoint(in rect: CGRect, onTop: (CGPoint) -> Bool) -> CGPoint? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    if onTop(center) { return center }
    for i in 1...5 {
        for j in 1...5 {
            let p = CGPoint(x: rect.minX + rect.width * CGFloat(i) / 6, y: rect.minY + rect.height * CGFloat(j) / 6)
            if onTop(p) { return p }
        }
    }
    return nil
}

/// Whether `inner` covers at least half of `outer`'s area.
func coversHalf(_ inner: CGRect, of outer: CGRect) -> Bool {
    let i = inner.intersection(outer)
    guard !i.isNull else { return false }
    return 2 * i.width * i.height >= outer.width * outer.height
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

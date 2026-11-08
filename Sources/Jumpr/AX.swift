import ApplicationServices
import JumprCore

// Private, but the only way to tie an accessibility window to its window-server ID.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ el: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Per-request timeout, so one hung app cannot hold a scan queue for the system default (6 s).
let axRequestTimeout: Float = 0.25

func now() -> Double { CFAbsoluteTimeGetCurrent() }

/// A live element as a hashable value: `==` is `CFEqual`, hash is `CFHash`.
struct AXBox: Hashable {
    let element: AXUIElement

    static func == (a: AXBox, b: AXBox) -> Bool { CFEqual(a.element, b.element) }
    func hash(into h: inout Hasher) { h.combine(CFHash(element)) }
}

func axElement(_ id: ElementID) -> AXUIElement? {
    (id.raw.base as? AXBox)?.element
}

/// The timeout applies per element object, so set it on every element we query.
@discardableResult
func axTimed(_ el: AXUIElement) -> AXUIElement {
    AXUIElementSetMessagingTimeout(el, axRequestTimeout)
    return el
}

func axApp(_ pid: Int32) -> AXUIElement {
    axTimed(AXUIElementCreateApplication(pid))
}

/// One round trip for several attributes; `nil` on error. Missing attributes come back as AXValue errors.
func axMulti(_ el: AXUIElement, _ names: CFArray) -> [AnyObject]? {
    axMultiResult(el, names).values
}

func axMultiResult(_ el: AXUIElement, _ names: CFArray) -> (values: [AnyObject]?, error: AXError) {
    var out: CFArray?
    let err = AXUIElementCopyMultipleAttributeValues(el, names, AXCopyMultipleAttributeOptions(), &out)
    return (err == .success ? out as? [AnyObject] : nil, err)
}

func axCopy(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

/// The actions the element offers (`AXPress`, `AXShowMenu`, …); nil if it did not answer.
func axActionNames(_ el: AXUIElement) -> [String]? {
    var names: CFArray?
    guard AXUIElementCopyActionNames(el, &names) == .success else { return nil }
    return names as? [String]
}

func axPoint(_ v: AnyObject) -> CGPoint? {
    guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
}

func axSize(_ v: AnyObject) -> CGSize? {
    guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
}

func axElements(_ v: AnyObject?) -> [AXUIElement] {
    guard let v, CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
    return (v as! [AnyObject]).compactMap(axElementValue)
}

func axElementValue(_ v: AnyObject) -> AXUIElement? {
    CFGetTypeID(v) == AXUIElementGetTypeID() ? (v as! AXUIElement) : nil
}

private let frameAttrs = ["AXPosition", "AXSize"] as CFArray

/// Current position + size, `nil` if the element is dead (or has no frame).
func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let a = axMulti(el, frameAttrs), a.count == 2,
          let p = axPoint(a[0]), let s = axSize(a[1]) else { return nil }
    return CGRect(origin: p, size: s)
}

// AXFocusableAncestor exists in web content only (Chromium and WebKit); elsewhere it comes
// back as an error value, which reads as "not focusable".
private let walkAttrs = ["AXRole", "AXPosition", "AXSize", "AXChildren", "AXEnabled", "AXFocusableAncestor", "AXSubrole"] as CFArray

/// A live accessibility element for `walk`.
final class AXElementNode: AXNode {
    let element: AXUIElement

    init(_ el: AXUIElement) {
        element = axTimed(el)
    }

    var id: ElementID { ElementID(AXBox(element: element)) }

    /// One `AXUIElementCopyMultipleAttributeValues` call.
    func info() -> NodeInfo? {
        guard let a = axMulti(element, walkAttrs), a.count == 7 else { return nil }
        var frame: CGRect?
        if let p = axPoint(a[1]), let s = axSize(a[2]) { frame = CGRect(origin: p, size: s) }
        return NodeInfo(role: a[0] as? String ?? "",
                        frame: frame,
                        enabled: a[4] as? Bool,
                        children: axElements(a[3]).map { AXElementNode($0) },
                        focusable: axElementValue(a[5]).map { CFEqual($0, element) } ?? false,
                        subrole: a[6] as? String)
    }

    func isSelected() -> Bool {
        (axCopy(element, "AXSelected") as? Bool) == true
    }

    func visibleRows() -> [any AXNode]? {
        axElements(axCopy(element, "AXVisibleRows")).map { AXElementNode($0) }
    }

    func offersPress() -> Bool {
        axActionNames(element)?.contains("AXPress") == true
    }

    func offersPageScroll() -> Bool {
        guard let actions = axActionNames(element) else { return false }
        return actions.contains("AXScrollDownByPage") || actions.contains("AXScrollUpByPage")
    }
}

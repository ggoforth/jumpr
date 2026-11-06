import Foundation

/// Observes one distributed notification with `.deliverImmediately`, and calls `handler`
/// on main. The block-based API uses the default suspension behavior, under which AppKit
/// may hold distributed notifications until the app is active; this menu bar app almost
/// never is, so a lock or trust-loss notification could arrive late.
final class DistributedObserver: NSObject {
    private let handler: () -> Void

    init(_ name: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(fire(_:)), name: Notification.Name(name), object: nil,
            suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func fire(_ note: Notification) {
        if Thread.isMainThread { handler() } else { DispatchQueue.main.async(execute: handler) }
    }
}

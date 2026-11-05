import Foundation

/// Calls `onChange` on main whenever a default changes, including changes
/// made by another process (`defaults write`).
final class DefaultsWatcher: NSObject {
    private let key: String
    private let onChange: () -> Void

    init(_ key: String, onChange: @escaping () -> Void) {
        self.key = key
        self.onChange = onChange
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: key, options: [.new], context: nil)
    }

    deinit { UserDefaults.standard.removeObserver(self, forKeyPath: key) }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == key else { return }
        if Thread.isMainThread { onChange() } else { DispatchQueue.main.async(execute: onChange) }
    }
}

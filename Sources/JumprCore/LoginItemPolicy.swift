import Foundation

public enum LoginItemPolicy {
    /// Jumpr registers itself as a login item on its own only once, and only when the
    /// bundle sits directly in /Applications: a build running from anywhere else never does.
    public static func shouldAutoRegister(bundlePath: String, alreadySetUp: Bool) -> Bool {
        guard !alreadySetUp, !bundlePath.isEmpty else { return false }
        let parent = URL(fileURLWithPath: bundlePath).standardizedFileURL.deletingLastPathComponent().path
        return parent == "/Applications"
    }
}

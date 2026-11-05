import Foundation

public enum UpdatePolicy {
    /// Development builds get this in place of a real Sparkle public key (scripts/build-app.sh).
    public static let placeholderPublicKey = "PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY"

    /// Whether the build carries a real feed and key, so the updater may start. A development
    /// build has the feed switched off (`file:///dev/null`) and the placeholder key; Sparkle
    /// refuses to start on a key that is not 32 bytes of base64 and shows the user an error,
    /// so such a build never starts it.
    public static func isConfigured(feedURL: String?, publicKey: String?) -> Bool {
        guard let feedURL, let url = URL(string: feedURL),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return false }
        guard let publicKey, publicKey != placeholderPublicKey,
              let key = Data(base64Encoded: publicKey), key.count == 32 else { return false }
        return true
    }
}

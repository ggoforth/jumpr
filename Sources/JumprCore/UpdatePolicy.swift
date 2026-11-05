import Foundation

public enum UpdatePolicy {
    /// Development builds get this in place of a real Sparkle public key (scripts/build-app.sh).
    public static let placeholderPublicKey = "PLACEHOLDER-NOT-A-REAL-SPARKLE-KEY"

    /// Whether the build carries a real feed and key, so the updater may start. A development
    /// build has the feed switched off (`file:///dev/null`) and the placeholder key; Sparkle
    /// refuses to start on a key that is not 32 bytes of base64 and shows the user an error,
    /// so such a build never starts it. scripts/build-app.sh applies the same rule to refuse a
    /// release build without a real feed and key.
    public static func isConfigured(feedURL: String?, publicKey: String?) -> Bool {
        guard let feedURL, let publicKey else { return false }
        return isRealFeedURL(feedURL) && isRealPublicKey(publicKey)
    }

    /// A release feed: https, a dotted host, an optional port, a path of plain URL characters.
    /// scripts/build-app.sh uses this exact pattern; keep the two identical.
    public static let feedPattern = #"^https://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:[0-9]+)?(/[A-Za-z0-9._~%!$&'()*+,;=:/-]*)?$"#

    /// Surrounding whitespace is ignored, as the build script trims it.
    public static func isRealFeedURL(_ feed: String) -> Bool {
        let trimmed = feed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: feedPattern, options: .regularExpression) != nil,
              let url = URL(string: trimmed), url.host?.isEmpty == false else { return false }
        return true
    }

    /// A Sparkle EdDSA public key: base64 that decodes to exactly 32 bytes. Surrounding
    /// whitespace is ignored; whitespace inside the key is not accepted.
    public static func isRealPublicKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != placeholderPublicKey, let data = Data(base64Encoded: trimmed) else { return false }
        return data.count == 32
    }
}

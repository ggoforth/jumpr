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
        guard let feedURL = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: feedURL),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return false }
        guard let publicKey else { return false }
        return isRealPublicKey(publicKey)
    }

    /// A Sparkle EdDSA public key: base64 that decodes to exactly 32 bytes. Surrounding
    /// whitespace is ignored; whitespace inside the key is not accepted.
    public static func isRealPublicKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != placeholderPublicKey, let data = Data(base64Encoded: trimmed) else { return false }
        return data.count == 32
    }
}

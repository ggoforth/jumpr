import JumprCore
import Testing

/// 32 bytes of base64, the shape of a Sparkle EdDSA public key (not a real one).
private let wellFormedKey = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="

@Test func realFeedAndKeyStartTheUpdater() {
    #expect(UpdatePolicy.isConfigured(feedURL: "https://example.com/appcast.xml", publicKey: wellFormedKey))
}

@Test func developmentDefaultsNeverStartTheUpdater() {
    #expect(!UpdatePolicy.isConfigured(feedURL: "file:///dev/null", publicKey: UpdatePolicy.placeholderPublicKey))
    #expect(!UpdatePolicy.isConfigured(feedURL: "https://example.com/appcast.xml", publicKey: UpdatePolicy.placeholderPublicKey))
    #expect(!UpdatePolicy.isConfigured(feedURL: "file:///dev/null", publicKey: wellFormedKey))
}

@Test func feedMustBeHTTPSWithAHost() {
    for feed in ["http://example.com/appcast.xml", "https://", "https:///appcast.xml", "example.com/appcast.xml", "", nil] {
        #expect(!UpdatePolicy.isConfigured(feedURL: feed, publicKey: wellFormedKey), "\(feed ?? "nil")")
    }
    #expect(UpdatePolicy.isConfigured(feedURL: "HTTPS://example.com/appcast.xml", publicKey: wellFormedKey))
}

@Test func keyMustBe32BytesOfBase64() {
    let feed = "https://example.com/appcast.xml"
    for key in ["", "not base64!", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHg==", nil] {  // the third is 31 bytes
        #expect(!UpdatePolicy.isConfigured(feedURL: feed, publicKey: key), "\(key ?? "nil")")
    }
}

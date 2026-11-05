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

@Test func keyOfAnyOtherLengthIsRejected() {
    let lengths = [
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHg==",      // 31 bytes
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8g",      // 33 bytes
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+Pw==",  // 64 bytes
    ]
    for key in lengths { #expect(!UpdatePolicy.isRealPublicKey(key), "\(key)") }
    #expect(UpdatePolicy.isRealPublicKey(wellFormedKey))
}

@Test func surroundingWhitespaceIsIgnoredInnerWhitespaceIsNot() {
    #expect(UpdatePolicy.isRealPublicKey("  \(wellFormedKey)\n"))
    #expect(UpdatePolicy.isConfigured(feedURL: " https://example.com/appcast.xml\n", publicKey: "\t\(wellFormedKey) "))
    #expect(!UpdatePolicy.isRealPublicKey("AAECAwQFBgcICQoLDA0ODxAR EhMUFRYXGBkaGxwdHh8="))
    #expect(!UpdatePolicy.isRealPublicKey("AAECAwQFBgcICQoLDA0ODxAR\nEhMUFRYXGBkaGxwdHh8="))
    #expect(!UpdatePolicy.isRealPublicKey("  \(UpdatePolicy.placeholderPublicKey) "))
}

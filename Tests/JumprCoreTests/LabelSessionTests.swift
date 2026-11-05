import Testing
@testable import JumprCore

@Test func typingNarrowsThenMatches() {
    var s = LabelSession(); s.labels = ["AA", "AS", "SD"]
    #expect(s.handle(.character("a")) == .narrowed("A"))
    #expect(s.handle(.character("S")) == .matched("AS"))
}

@Test func unknownLettersAreSwallowed() {
    var s = LabelSession(); s.labels = ["AA"]
    #expect(s.handle(.character("Q")) == .swallow)
    #expect(s.typed == "")
    #expect(s.handle(.other) == .swallow)
}

@Test func backspaceEscapeHotkeyModified() {
    var s = LabelSession(); s.labels = ["AA", "AS"]
    #expect(s.handle(.backspace) == .swallow)
    _ = s.handle(.character("A"))
    #expect(s.handle(.backspace) == .narrowed(""))
    #expect(s.handle(.modified) == .passThrough)
    #expect(s.handle(.escape) == .cancelled)
    #expect(s.handle(.hotkey) == .cancelled)
}

@Test func labelsAddedMidSessionCanMatch() {
    var s = LabelSession(); s.labels = ["AA"]
    #expect(s.handle(.character("S")) == .swallow)
    s.labels.insert("SD")
    #expect(s.handle(.character("S")) == .narrowed("S"))
    #expect(s.handle(.character("D")) == .matched("SD"))
}

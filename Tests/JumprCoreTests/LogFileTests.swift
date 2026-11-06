import JumprCore
import Testing

@Test func logRotatesOnlyWhenTheLineWouldPassTheCap() {
    #expect(!LogFile.shouldRotate(size: 900, adding: 100, cap: 1000))   // lands exactly on the cap
    #expect(LogFile.shouldRotate(size: 901, adding: 100, cap: 1000))
    #expect(LogFile.shouldRotate(size: 5000, adding: 1, cap: 1000))     // an old log already over
}

@Test func anEmptyLogTakesALineLongerThanTheCap() {
    #expect(!LogFile.shouldRotate(size: 0, adding: 2000, cap: 1000))
}

@Test func theCapIsOneMegabyte() {
    #expect(LogFile.cap == 1_000_000)
    #expect(!LogFile.shouldRotate(size: 999_000, adding: 100))
    #expect(LogFile.shouldRotate(size: 999_950, adding: 100))
}

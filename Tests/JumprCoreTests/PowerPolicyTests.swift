import Testing
@testable import JumprCore

@Test func noLockCauseIsUnlocked() {
    #expect(!LockCauses().locked)
}

@Test func anyLockCauseLocks() {
    #expect(LockCauses(sessionLocked: true).locked)
    #expect(LockCauses(displaysAsleep: true).locked)
    #expect(LockCauses(screenSaver: true).locked)
}

@Test func endingOneCauseKeepsTheOthers() {
    var c = LockCauses(sessionLocked: true, displaysAsleep: false, screenSaver: true)
    c.sessionLocked = false  // unlocked while the screen saver still runs
    #expect(c.locked)
    c.screenSaver = false
    #expect(!c.locked)
}

@Test func userActivityClearsSleepAndScreenSaver() {
    var c = LockCauses(sessionLocked: false, displaysAsleep: true, screenSaver: true)
    c.noteUserActivity(sessionLockedNow: false)
    #expect(c == LockCauses())
    #expect(!c.locked)
}

@Test func userActivityResyncsTheSessionLockToTheLiveValue() {
    var stale = LockCauses(sessionLocked: true)  // missed screenIsUnlocked
    stale.noteUserActivity(sessionLockedNow: false)
    #expect(!stale.locked)
    var missed = LockCauses(displaysAsleep: true)  // missed screenIsLocked
    missed.noteUserActivity(sessionLockedNow: true)
    #expect(missed == LockCauses(sessionLocked: true))
    #expect(missed.locked)
}

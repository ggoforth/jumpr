import Testing
@testable import JumprCore

private func s(battery: Bool = false, low: Bool = false, locked: Bool = false, paused: Bool = false) -> PowerState {
    PowerState(onBattery: battery, lowPower: low, locked: locked, paused: paused)
}

@Test func pluggedInIsAlwaysAll() {
    for m in BatteryMode.allCases { #expect(warmth(s(), mode: m) == .all) }
}

@Test func batteryFollowsTheSetting() {
    #expect(warmth(s(battery: true), mode: .full) == .all)
    #expect(warmth(s(battery: true), mode: .frontApp) == .frontApp)
    #expect(warmth(s(battery: true), mode: .onDemand) == .none)
}

@Test func lowPowerModeCountsAsBattery() {
    #expect(warmth(s(low: true), mode: .frontApp) == .frontApp)
}

@Test func lockedOrPausedIsNone() {
    #expect(warmth(s(locked: true), mode: .full) == .none)
    #expect(warmth(s(paused: true), mode: .full) == .none)
}

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

@Test func userActivityClearsSleepAndScreenSaverButNotTheSessionLock() {
    var c = LockCauses(sessionLocked: false, displaysAsleep: true, screenSaver: true)
    c.noteUserActivity()
    #expect(c == LockCauses())
    var l = LockCauses(sessionLocked: true, displaysAsleep: true, screenSaver: true)
    l.noteUserActivity()
    #expect(l == LockCauses(sessionLocked: true))
    #expect(l.locked)
}

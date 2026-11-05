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

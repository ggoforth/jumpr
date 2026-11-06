public struct PowerState: Equatable {
    public var onBattery: Bool
    public var lowPower: Bool
    public var locked: Bool
    public var paused: Bool

    public init(onBattery: Bool, lowPower: Bool, locked: Bool, paused: Bool) {
        self.onBattery = onBattery
        self.lowPower = lowPower
        self.locked = locked
        self.paused = paused
    }
}

/// The three things that make the screen unusable, tracked apart so that one
/// ending (an unlock, say) cannot clear another that still holds.
public struct LockCauses: Equatable {
    public var sessionLocked = false
    public var displaysAsleep = false
    public var screenSaver = false

    public init(sessionLocked: Bool = false, displaysAsleep: Bool = false, screenSaver: Bool = false) {
        self.sessionLocked = sessionLocked
        self.displaysAsleep = displaysAsleep
        self.screenSaver = screenSaver
    }

    /// Locked while any cause holds.
    public var locked: Bool { sessionLocked || displaysAsleep || screenSaver }

    /// The user just pressed a key: the displays are awake and no screen saver runs,
    /// whatever the notifications last said. The session lock is resynced to the live
    /// value (a missed unlock or lock notification is corrected), not cleared.
    public mutating func noteUserActivity(sessionLockedNow: Bool) {
        displaysAsleep = false
        screenSaver = false
        sessionLocked = sessionLockedNow
    }
}

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

public enum Warmth: Equatable {
    case all
    case frontApp
    case none
}

/// Which windows the watcher keeps warm. Locked or paused: none. Plugged in
/// and not in Low Power Mode: all. Otherwise the battery setting decides.
public func warmth(_ s: PowerState, mode: BatteryMode) -> Warmth {
    if s.locked || s.paused { return .none }
    if !s.onBattery && !s.lowPower { return .all }
    switch mode {
    case .full: return .all
    case .frontApp: return .frontApp
    case .onDemand: return .none
    }
}

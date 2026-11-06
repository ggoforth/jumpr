import CoreGraphics

public struct Shown: Equatable {
    public let label: String
    public let target: Target

    public init(label: String, target: Target) {
        self.label = label
        self.target = target
    }
}

public struct Moved: Equatable {
    public let label: String
    public let target: Target

    public init(label: String, target: Target) {
        self.label = label
        self.target = target
    }
}

public struct FixUp: Equatable {
    public var remove: [String]
    public var move: [Moved]
    public var add: [Target]

    public init(remove: [String], move: [Moved], add: [Target]) {
        self.remove = remove
        self.move = move
        self.add = add
    }
}

/// Compares the labels on screen with a fresh scan of one window (or one app's
/// system pieces), matching by `Target.id`. Labels are never reassigned.
public func fixUp(shown: [Shown], fresh: [Target]) -> FixUp {
    var freshByID: [ElementID: Target] = [:]
    for target in fresh { freshByID[target.id] = target }

    var remove: [String] = []
    var move: [Moved] = []
    var shownIDs = Set<ElementID>()
    for s in shown {
        shownIDs.insert(s.target.id)
        guard let now = freshByID[s.target.id] else {
            remove.append(s.label)
            continue
        }
        if now.rect != s.target.rect {
            move.append(Moved(label: s.label, target: now))
        }
    }
    let add = fresh.filter { !shownIDs.contains($0.id) }
    return FixUp(remove: remove, move: move, add: add)
}

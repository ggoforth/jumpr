import CoreGraphics

/// The labels on screen in one session, so a label can make room for its neighbours.
///
/// The window buttons (16 pt wide on a 23 pt pitch) and TextEdit's formatting bar (buttons
/// about 20 pt apart) sit closer together than a label is wide, and their labels covered each
/// other. Neighbours that crowd get smaller labels, in the same place (`Labels.frame`'s
/// `drawnAt`): a label that moved to another side could hide its own control or the next one.
public struct LabelLayout {
    public struct Spot: Equatable {
        public let rect: CGRect  // the label's frame, global top-left coordinates
        public let size: CGFloat  // the font size it is drawn at
    }

    private struct Entry {
        let target: CGRect
        let screen: CGRect
        let full: CGRect  // the frame at the full size, which decides who is a neighbour
        var spot: Spot
    }

    private struct Cell: Hashable {
        let x: Int, y: Int
    }

    private let length: Int
    private let fontSize: CGFloat
    private let advance: CGFloat
    private let cellW: CGFloat
    private let cellH: CGFloat
    private var entries: [String: Entry] = [:]
    /// Each label under every cell its full frame touches. A cell is one full label box, so
    /// labels that overlap share a cell, and a newcomer is checked against a handful of labels,
    /// not the hundreds on screen.
    private var grid: [Cell: [String]] = [:]

    public init(length: Int, fontSize: CGFloat, advance: CGFloat) {
        self.length = length
        self.fontSize = fontSize
        self.advance = advance
        // Every full-size label in a layout is the same size, wherever it goes.
        let box = Labels.frame(length: length, target: .zero, screen: CGRect(x: 0, y: 0, width: 1e6, height: 1e6),
                               fontSize: fontSize, advance: advance)
        cellW = max(box.width, 1)
        cellH = max(box.height, 1)
    }

    /// The new label's spot, under its own letters, and the new spot of every label
    /// already there that had to get smaller to make room.
    public mutating func add(_ label: String, target: CGRect, screen: CGRect) -> [String: Spot] {
        let full = Labels.frame(length: length, target: target, screen: screen, fontSize: fontSize, advance: advance)
        // Neighbours by full frames: with close, minimize, then zoom, minimize is already small
        // and its small box misses zoom's full one, but all three must end at one size.
        var neighbours: [String] = []
        for cell in cells(of: full) {
            for other in grid[cell] ?? [] where !neighbours.contains(other) {
                if let e = entries[other], Self.crowd(full, fontSize, e.full, fontSize) { neighbours.append(other) }
            }
        }
        var size = fontSize
        if !neighbours.isEmpty {
            size = neighbours.reduce(fontSize) { min($0, entries[$1]!.spot.size) }
            let floor = CGFloat(smallestLabelSize)
            while size > floor && crowds(target, screen, at: size, neighbours) { size = max(size - 1, floor) }
        }
        let spot = Spot(rect: frame(target, screen, at: size), size: size)
        var changed = [label: spot]
        for other in neighbours {
            guard let e = entries[other], e.spot.size > size else { continue }  // smaller keeps its own
            let s = Spot(rect: frame(e.target, e.screen, at: size), size: size)
            entries[other]?.spot = s
            changed[other] = s
        }
        entries[label] = Entry(target: target, screen: screen, full: full, spot: spot)
        for cell in cells(of: full) { grid[cell, default: []].append(label) }
        return changed
    }

    /// Forgets a label. A label it made smaller stays as it is: growing back would move it
    /// under the person's eyes.
    public mutating func remove(_ label: String) {
        guard let e = entries.removeValue(forKey: label) else { return }
        for cell in cells(of: e.full) { grid[cell]?.removeAll { $0 == label } }
    }

    /// The newcomer drawn at `size` crowds a neighbour drawn at the smaller of its own size and `size`.
    private func crowds(_ target: CGRect, _ screen: CGRect, at size: CGFloat, _ neighbours: [String]) -> Bool {
        let mine = frame(target, screen, at: size)
        return neighbours.contains { other in
            let e = entries[other]!
            let s = min(e.spot.size, size)
            return Self.crowd(mine, size, frame(e.target, e.screen, at: s), s)
        }
    }

    private func frame(_ target: CGRect, _ screen: CGRect, at size: CGFloat) -> CGRect {
        Labels.frame(length: length, target: target, screen: screen, fontSize: fontSize, advance: advance, drawnAt: size)
    }

    private func cells(of r: CGRect) -> [Cell] {
        let x0 = Int((r.minX / cellW).rounded(.down)), x1 = Int((r.maxX / cellW).rounded(.down))
        let y0 = Int((r.minY / cellH).rounded(.down)), y1 = Int((r.maxY / cellH).rounded(.down))
        var out: [Cell] = []
        for x in x0...x1 { for y in y0...y1 { out.append(Cell(x: x, y: y)) } }
        return out
    }

    /// Overlapping by more than a tenth of the font size across and two fifths of it down. Less
    /// only touches margins: a hanging label already overlaps its own target two fifths down,
    /// so a row's label and the label of a button inside the row meet that much in every list.
    private static func crowd(_ a: CGRect, _ aSize: CGFloat, _ b: CGRect, _ bSize: CGFloat) -> Bool {
        let size = min(aSize, bSize)
        let across = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let down = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return across > size / 10 && down > size * 2 / 5
    }
}

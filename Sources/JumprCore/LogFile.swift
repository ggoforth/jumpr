public enum LogFile {
    /// The log keeps at most about this many bytes, plus one older file of the same size,
    /// so a Jumpr left running for months cannot fill a disk.
    public static let cap = 1_000_000

    /// Whether a log already `size` bytes long should be moved aside before `adding` more.
    /// An empty log never is: a single line over the cap is still written.
    public static func shouldRotate(size: Int, adding: Int, cap: Int = cap) -> Bool {
        size > 0 && size + adding > cap
    }
}

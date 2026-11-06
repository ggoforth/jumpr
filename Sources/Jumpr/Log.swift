import Foundation
import JumprCore

private let logQueue = DispatchQueue(label: "jumpr.log")
private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Jumpr.log")
private let oldLogURL = logURL.appendingPathExtension("1")
/// Bytes in the log file: read from disk once, then counted. Only touched on `logQueue`.
private var logSize: Int?

/// Blocks until every line logged so far is written. For use just before the process exits.
func flushLog() {
    logQueue.sync {}
}

/// Appends a timestamped line to ~/Library/Logs/Jumpr.log. Thread-safe. Past
/// `LogFile.cap` the log moves to Jumpr.log.1 (replacing the one there) and starts again.
func log(_ s: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(s)\n"
    logQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        var size = logSize
            ?? ((try? fm.attributesOfItem(atPath: logURL.path)[.size]) as? NSNumber)?.intValue ?? 0
        if LogFile.shouldRotate(size: size, adding: data.count) {
            try? fm.removeItem(at: oldLogURL)
            try? fm.moveItem(at: logURL, to: oldLogURL)
            size = 0
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
        logSize = size + data.count
    }
}

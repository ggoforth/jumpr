import Foundation

private let logQueue = DispatchQueue(label: "jumpr.log")
private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Jumpr.log")

/// Appends a timestamped line to ~/Library/Logs/Jumpr.log. Thread-safe.
func log(_ s: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(s)\n"
    logQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}

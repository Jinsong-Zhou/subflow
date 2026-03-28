import Foundation

/// Writes logs to ~/Library/Logs/SubFlow.log for easy debugging.
/// Usage: AppLogger.log("message") or AppLogger.log("context", "detail")
enum AppLogger {
    private static let logURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("SubFlow.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ items: Any...) {
        let timestamp = formatter.string(from: Date())
        let message = items.map { "\($0)" }.joined(separator: " ")
        let line = "[\(timestamp)] \(message)\n"

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Clear the log file (call on app launch)
    static func clear() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }

    static var path: String { logURL.path }
}

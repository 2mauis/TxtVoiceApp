import Foundation

enum AppLogger {
    static var logURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("txtnovelreader", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        return root.appendingPathComponent("app.log")
    }

    static func info(_ message: String, category: String = "app") {
        write(level: "INFO", category: category, message: message)
    }

    static func warning(_ message: String, category: String = "app") {
        write(level: "WARN", category: category, message: message)
    }

    static func error(_ message: String, category: String = "app") {
        write(level: "ERROR", category: category, message: message)
    }

    static func snippet(_ text: String, limit: Int = 240) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)) + "..."
    }

    private static func write(level: String, category: String, message: String) {
        let line = "\(Self.timestamp()) [\(level)] [\(category)] \(message)\n"
        DispatchQueue.global(qos: .utility).async {
            do {
                let url = Self.logURL
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                guard let data = line.data(using: .utf8) else { return }
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url, options: [.atomic])
                }
            } catch {
                NSLog("txtnovelreader log write failed: \(error.localizedDescription)")
            }
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

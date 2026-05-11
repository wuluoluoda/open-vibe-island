import Foundation

enum NotificationDebugLog {
    private static let queue = DispatchQueue(label: "app.openisland.notification-debug-log")

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/open-island", isDirectory: true)
            .appendingPathComponent("notification-debug.log")
    }

    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async {
            append(line)
        }
    }

    private static func append(_ line: String) {
        let data = Data(line.utf8)
        let url = fileURL
        let directoryURL = url.deletingLastPathComponent()
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer {
                    try? handle.close()
                }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            NSLog("[OpenIsland] notification debug log write failed: %@", String(describing: error))
        }
    }
}

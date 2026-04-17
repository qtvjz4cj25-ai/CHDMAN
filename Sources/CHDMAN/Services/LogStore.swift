import Foundation

/// Thread-safe, actor-based log store.
/// Accumulates a global log and writes it to disk on every append.
actor LogStore {

    private(set) var logFileURL: URL?
    private var fileHandle: FileHandle?

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("CHDMAN", isDirectory: true)

        if let dir {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let name = "chdman-\(Self.datestamp()).log"
            logFileURL = dir.appendingPathComponent(name)
            if let logFileURL {
                _ = FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
                fileHandle = try? FileHandle(forWritingTo: logFileURL)
                _ = try? fileHandle?.seekToEnd()
            }
        }
    }

    func appendGlobal(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        do {
            try fileHandle?.write(contentsOf: data)
        } catch {
            guard let url = logFileURL else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                fileHandle = handle
                _ = try? fileHandle?.seekToEnd()
                _ = try? fileHandle?.write(contentsOf: data)
            }
        }
    }

    deinit {
        _ = try? fileHandle?.close()
    }

    private static func datestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: Date())
    }
}

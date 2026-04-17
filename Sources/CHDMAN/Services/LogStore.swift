import Foundation

/// Thread-safe, actor-based log store.
/// Accumulates a global log and writes it to disk on every append.
actor LogStore {

    private var globalLines: [String] = []
    private(set) var logFileURL: URL?

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
        }
    }

    func appendGlobal(_ line: String) {
        globalLines.append(line)
        flush()
    }

    // MARK: - Private

    private func flush() {
        guard let url = logFileURL else { return }
        let text = globalLines.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: false, encoding: .utf8)
    }

    private static func datestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: Date())
    }
}

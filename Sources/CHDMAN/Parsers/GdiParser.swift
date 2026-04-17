import Foundation

/// Parses a Dreamcast .gdi file and returns the URLs of all referenced track
/// files so they can be deleted after a successful conversion.
///
/// GDI format:
///   Line 1 : track count  (integer)
///   Line 2+: <track#> <lba> <type> <sectorSize> <filename> <unknown>
///
/// Example:
///   3
///   1 0 4 2352 track01.bin 0
///   2 600 0 2048 track02.iso 0
///   3 45000 4 2352 track03.bin 0
///
/// Relative paths are resolved against the directory containing the .gdi file.
struct GdiParser {

    enum GdiParserError: Error {
        case cannotReadFile(URL)
    }

    /// Returns a list of file URLs referenced by track lines in the .gdi.
    /// Ignores the first line (track count) and malformed lines silently.
    func referencedFiles(gdiURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: gdiURL.path) else {
            throw GdiParserError.cannotReadFile(gdiURL)
        }

        let content: String
        if let utf8Content = try? String(contentsOf: gdiURL, encoding: .utf8) {
            content = utf8Content
        } else if let latin1Content = try? String(contentsOf: gdiURL, encoding: .isoLatin1) {
            content = latin1Content
        } else {
            throw GdiParserError.cannotReadFile(gdiURL)
        }

        let baseDir = gdiURL.deletingLastPathComponent()
        var results: [URL] = []
        var seen: Set<String> = []
        var lineIndex = 0

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // First non-empty line is the track count — skip it.
            if lineIndex == 0 {
                lineIndex += 1
                continue
            }
            lineIndex += 1

            if let filename = extractFilename(from: line) {
                let resolved = baseDir.appendingPathComponent(filename).standardizedFileURL
                let key = resolved.path
                if !seen.contains(key) {
                    seen.insert(key)
                    results.append(resolved)
                }
            }
        }

        return results
    }

    // MARK: - Private

    /// GDI track line: "1 0 4 2352 track01.bin 0"
    /// The filename is the fifth field, followed by a trailing numeric flag.
    /// Quoted filenames are supported to allow spaces in track names.
    private func extractFilename(from line: String) -> String? {
        // Split the first four fields, keeping the filename/trailing-flag payload intact.
        let fields = line.split(
            maxSplits: 4,
            omittingEmptySubsequences: true,
            whereSeparator: { $0.isWhitespace }
        )
        guard fields.count == 5 else { return nil }

        let payload = String(fields[4]).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }

        let candidate: String
        if payload.hasPrefix("\"") {
            let quoted = String(payload.dropFirst())
            guard let endQuote = quoted.firstIndex(of: "\"") else { return nil }
            candidate = String(quoted[..<endQuote])
        } else if let separator = payload.lastIndex(where: { $0.isWhitespace }) {
            candidate = String(payload[..<separator]).trimmingCharacters(in: .whitespaces)
        } else {
            candidate = payload
        }

        guard !candidate.isEmpty, candidate.contains(".") else { return nil }
        return candidate
    }
}

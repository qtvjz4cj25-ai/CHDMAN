import Foundation

/// Parses a .cue file and returns the URLs of all referenced data files so
/// they can be deleted after a successful conversion.
///
/// Supported syntax (subset of the Redbook CUE spec):
///
///   FILE "filename.bin" BINARY
///   FILE filename.bin BINARY
///   FILE "path with spaces.bin" BINARY
///
/// Relative paths are resolved against the directory containing the .cue file.
struct CueParser {

    enum CueParserError: Error {
        case cannotReadFile(URL)
    }

    /// Returns a list of file URLs referenced by `FILE` directives in the cue.
    /// Ignores malformed lines silently.
    func referencedFiles(cueURL: URL) throws -> [URL] {
        let content: String
        do {
            content = try String(contentsOf: cueURL, encoding: .utf8)
        } catch {
            do {
                content = try String(contentsOf: cueURL, encoding: .isoLatin1)
            } catch {
                throw CueParserError.cannotReadFile(cueURL)
            }
        }

        let baseDir = cueURL.deletingLastPathComponent()
        var results: [URL] = []
        var seen: Set<String> = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("FILE") else { continue }

            if let filename = extractFilename(from: line) {
                // Resolve relative path.
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

    /// Extracts the filename argument from a CUE FILE line.
    /// Handles:
    ///   FILE "name with spaces.bin" BINARY
    ///   FILE noSpaces.bin BINARY
    private func extractFilename(from line: String) -> String? {
        // Drop "FILE" prefix (case-insensitive).
        var rest = line
        if rest.lowercased().hasPrefix("file") {
            rest = String(rest.dropFirst(4))
        }
        rest = rest.trimmingCharacters(in: .whitespaces)

        if rest.hasPrefix("\"") {
            // Quoted filename — find closing quote.
            rest = String(rest.dropFirst())
            guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[rest.startIndex..<endQuote])
        } else {
            // Unquoted — filename ends at next whitespace.
            let parts = rest.components(separatedBy: .whitespaces)
            guard let first = parts.first, !first.isEmpty else { return nil }
            return first
        }
    }
}

import Foundation

/// Scans a directory tree for supported disc-image source files and produces
/// a deduplicated list of ConversionJob objects.
struct FolderScanner: Sendable {

    /// Runs file-system enumeration off the main thread, then creates the
    /// @MainActor ConversionJob objects back on the main actor.
    @MainActor
    func scan(folder: URL, recursive: Bool) async -> [ConversionJob] {
        // Heavy FS work on a background priority executor.
        let found: [(URL, SourceType)] = await Task.detached(priority: .userInitiated) {
            Self.enumerateFiles(folder: folder, recursive: recursive)
        }.value

        // ConversionJob is @MainActor — create them here on the main actor.
        return found.map { (url, type) in
            let output = url.deletingPathExtension().appendingPathExtension("chd")
            return ConversionJob(sourceURL: url, sourceType: type, outputURL: output)
        }
    }

    // MARK: - Pure FS enumeration (no UI objects, Sendable context)

    private static func enumerateFiles(
        folder: URL,
        recursive: Bool
    ) -> [(URL, SourceType)] {
        let fm = FileManager.default
        let skipOptions: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: skipOptions
        ) else { return [] }

        var results: [(URL, SourceType)] = []
        var seen: Set<String> = []

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            let type: SourceType
            switch url.pathExtension.lowercased() {
            case "iso": type = .iso
            case "cue": type = .cue
            case "gdi": type = .gdi
            default:    continue
            }

            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append((url, type))
        }

        // Deterministic ordering: ISOs first, then CUEs, then GDIs; within each by path.
        results.sort {
            let orderA = sortKey($0.1), orderB = sortKey($1.1)
            if orderA != orderB { return orderA < orderB }
            return $0.0.path < $1.0.path
        }
        return results
    }

    private static func sortKey(_ t: SourceType) -> Int {
        switch t {
        case .iso: return 0
        case .cue: return 1
        case .gdi: return 2
        }
    }
}

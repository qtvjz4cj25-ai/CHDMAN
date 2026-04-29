import Foundation

/// Converts between Xbox OG game directories and XISO image files using extract-xiso.
///
/// Create:  Xbox game folder (contains default.xbe) → XISO `.iso`
///   Command: extract-xiso -c <source_dir> <output.iso>
///
/// Extract: XISO `.iso` → Xbox game folder (directory)
///   Command: extract-xiso <source.iso> -d <output_dir>
final class ExtractXisoEngine: BatchEngine {

    let extractXisoPath: String
    let mode: AppMode

    init(
        extractXisoPath: String,
        mode: AppMode,
        concurrency: Int,
        jobs: [ConversionJob],
        logStore: LogStore,
        deleteSource: Bool = false
    ) {
        self.extractXisoPath = extractXisoPath
        self.mode = mode
        super.init(concurrency: concurrency, jobs: jobs, logStore: logStore, deleteSource: deleteSource)
    }

    // MARK: - Override: convert

    override func convert(_ job: ConversionJob, snapshot: JobSnapshot) async -> Bool {
        let args = buildArgs(snapshot: snapshot)

        // For extract mode, create the output directory first
        if mode == .extract {
            try? FileManager.default.createDirectory(
                atPath: snapshot.outputPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        guard let r = await runTool(
            executablePath: extractXisoPath,
            job: job,
            snapshot: snapshot,
            args: args
        ) else { return false }

        let succeeded: Bool
        switch mode {
        case .create:
            succeeded = r.succeeded && outputValid(snapshot.outputPath)
            if !succeeded { removeInvalidOutput(snapshot.outputPath) }
        case .extract:
            succeeded = r.succeeded && outputDirValid(snapshot.outputPath)
            if !succeeded { try? FileManager.default.removeItem(atPath: snapshot.outputPath) }
        }

        if !succeeded {
            if wasCancelled() { return false }
            let msg = "[\(ts())] [FAIL] \(snapshot.filename) — extract-xiso conversion failed."
            await setJob(job, status: .failed, detail: "Conversion failed", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return false
        }

        return true
    }

    // MARK: - Build arguments

    private func buildArgs(snapshot: JobSnapshot) -> [String] {
        switch mode {
        case .create:
            // extract-xiso -c <source_dir> <output.iso>
            return ["-c", snapshot.path, snapshot.outputPath]
        case .extract:
            // extract-xiso <source.iso> -d <output_dir>
            return [snapshot.path, "-d", snapshot.outputPath]
        }
    }

    // MARK: - Output validation for extract (directory)

    private func outputDirValid(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        return !((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).isEmpty
    }

    // MARK: - Cleanup

    override func cleanupSource(_ snapshot: JobSnapshot) {
        // For create mode source is a directory; for extract it's a file.
        // Both cases: just delete the source URL (file or dir).
        safeDelete(snapshot.sourceURL)
    }
}

import Foundation

enum ChdmanLocatorError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "chdman not found. Install it with: brew install rom-tools"
        }
    }
}

/// Finds the chdman executable and interrogates it for supported subcommands.
struct ChdmanLocator {

    private let knownPaths = [
        "/opt/homebrew/bin/chdman",
        "/usr/local/bin/chdman"
    ]

    // MARK: - Locate

    func locate(customPath: String?) async throws -> String {
        // 1. Custom path wins if it exists and is executable.
        if let custom = customPath, !custom.isEmpty {
            if isExecutable(at: custom) { return custom }
        }

        // 2. Known Homebrew locations.
        for path in knownPaths {
            if isExecutable(at: path) { return path }
        }

        // 3. PATH lookup via `which`.
        if let path = await which("chdman") {
            return path
        }

        throw ChdmanLocatorError.notFound
    }

    // MARK: - Capability detection

    func detectCapabilities(chdmanPath: String) async throws -> ChdmanCapabilities {
        // Run `chdman` with no arguments; it prints usage to stdout or stderr.
        let result = try await runQuiet(executablePath: chdmanPath, arguments: [])
        let combined = result.stdout + result.stderr

        let hasCreateCD   = combined.range(of: "createcd",   options: .caseInsensitive) != nil
        let hasCreateDVD  = combined.range(of: "createdvd",  options: .caseInsensitive) != nil
        let hasExtractCD  = combined.range(of: "extractcd",  options: .caseInsensitive) != nil
        let hasExtractDVD = combined.range(of: "extractdvd", options: .caseInsensitive) != nil

        return ChdmanCapabilities(
            hasCreateCD:   hasCreateCD,
            hasCreateDVD:  hasCreateDVD,
            hasExtractCD:  hasExtractCD,
            hasExtractDVD: hasExtractDVD,
            rawHelpText:   combined
        )
    }

    // MARK: - Helpers

    private func isExecutable(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private func which(_ tool: String) async -> String? {
        guard let result = try? await runQuiet(executablePath: "/usr/bin/which", arguments: [tool]),
              result.exitCode == 0
        else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Minimal synchronous-style runner used only for quick capability queries.
    private func runQuiet(executablePath: String, arguments: [String]) async throws
        -> (exitCode: Int32, stdout: String, stderr: String)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout  = String(data: outData, encoding: .utf8) ?? ""
                let stderr  = String(data: errData, encoding: .utf8) ?? ""
                cont.resume(returning: (proc.terminationStatus, stdout, stderr))
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

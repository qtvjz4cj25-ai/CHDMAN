import Foundation

enum ExtractXisoLocatorError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "extract-xiso not found. Install via Homebrew (brew install extract-xiso) or build from source and set the path in Settings."
    }
}

/// Finds the extract-xiso executable for Xbox OG ISO create/extract operations.
/// Typically installed via Homebrew or built from source (github.com/xboxdev/extract-xiso).
struct ExtractXisoLocator {

    private let knownPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin/extract-xiso",
            "/usr/local/bin/extract-xiso",
            "\(home)/bin/extract-xiso",
            "\(home)/.local/bin/extract-xiso",
        ]
    }()

    // MARK: - Locate

    func locate(customPath: String?) async throws -> String {
        if let custom = customPath, !custom.isEmpty {
            if fileExists(at: custom) { return custom }
        }

        for path in knownPaths {
            if isExecutable(at: path) { return path }
        }

        if let path = await which("extract-xiso") { return path }

        throw ExtractXisoLocatorError.notFound
    }

    // MARK: - Verify

    func verify(path: String) async -> Bool {
        if let result = try? await runQuiet(executablePath: path, arguments: ["-h"]) {
            let combined = result.stdout + result.stderr
            if combined.range(of: "xiso", options: .caseInsensitive) != nil { return true }
            if combined.range(of: "extract", options: .caseInsensitive) != nil { return true }
        }
        return isExecutable(at: path)
    }

    // MARK: - Helpers

    func isExecutable(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func which(_ tool: String) async -> String? {
        guard let result = try? await runQuiet(executablePath: "/usr/bin/which", arguments: [tool]),
              result.exitCode == 0
        else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func runQuiet(executablePath: String, arguments: [String]) async throws
        -> (exitCode: Int32, stdout: String, stderr: String)
    {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe

            try process.run()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            let stdout = String(data: outData, encoding: .utf8) ?? ""
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout, stderr)
        }.value
    }
}

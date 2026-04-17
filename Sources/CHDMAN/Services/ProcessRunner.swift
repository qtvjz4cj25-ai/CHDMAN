import Foundation

// MARK: - ProcessResult

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout:   String
    let stderr:   String

    var succeeded: Bool { exitCode == 0 }
    var combinedOutput: String { stdout + (stderr.isEmpty ? "" : "\n[stderr]\n" + stderr) }
}

// MARK: - ProcessRunner

/// Runs a child process and streams its output line-by-line via an async callback.
/// Supports cooperative cancellation: if the enclosing Task is cancelled the
/// child process receives SIGTERM.
struct ProcessRunner {

    /// Run a process, calling `lineHandler` for every chunk of text produced.
    /// - Returns: The exit code and full captured output after the process exits.
    func run(
        executablePath: String,
        arguments: [String],
        lineHandler: @escaping (String) async -> Void,
        processCreated: @escaping (Process) -> Void = { _ in },
        processEnded:   @Sendable @escaping () -> Void = {}
    ) async throws -> ProcessResult {

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments     = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        // Shared mutable state accessed only from the termination handler /
        // readability handlers, which are serialised by design.
        final class Accumulator: @unchecked Sendable {
            var stdout = ""
            var stderr = ""
        }
        let acc = Accumulator()

        // AsyncStream to bridge pipe callbacks → async for-in loop.
        let (stream, continuation) = AsyncStream<String>.makeStream(
            bufferingPolicy: .unbounded
        )

        // stdout
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8)
            else { return }
            acc.stdout += text
            continuation.yield(text)
        }

        // stderr
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8)
            else { return }
            acc.stderr += text
            continuation.yield("[stderr] " + text)
        }

        // Termination: read any tail bytes, then close the stream.
        process.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            // Drain any bytes buffered before the handler fired.
            let tailOut = outPipe.fileHandleForReading.readDataToEndOfFile()
            let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()

            if let t = String(data: tailOut, encoding: .utf8), !t.isEmpty {
                acc.stdout += t
                continuation.yield(t)
            }
            if let t = String(data: tailErr, encoding: .utf8), !t.isEmpty {
                acc.stderr += t
                continuation.yield("[stderr] " + t)
            }
            continuation.finish()
            processEnded()
        }

        // withTaskCancellationHandler ensures the child is killed if our Task
        // is cancelled before it exits normally.
        return try await withTaskCancellationHandler {
            // Bail immediately if already cancelled before we even launch.
            try Task.checkCancellation()
            // Launch.
            try process.run()
            processCreated(process)

            // Drain the stream, forwarding each chunk to the caller.
            for await chunk in stream {
                // Forward to UI / log, breaking on long lines.
                let lines = chunk.components(separatedBy: "\n")
                for line in lines where !line.isEmpty {
                    await lineHandler(line)
                }
            }

            // The terminationHandler has already called continuation.finish(),
            // so the for-in loop above has exited.  The process is done.
            try Task.checkCancellation()

            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout:   acc.stdout,
                stderr:   acc.stderr
            )
        } onCancel: {
            process.terminate()
        }
    }
}

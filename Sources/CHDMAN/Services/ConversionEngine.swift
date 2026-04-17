import Foundation

// MARK: - Internal concurrency primitives

/// A Swift-concurrency semaphore: limits the number of concurrently running tasks.
private actor AsyncSemaphore {
    private var slots: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { slots = max(1, count) }

    func wait() async {
        if slots > 0 {
            slots -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            slots += 1
        }
    }
}

/// Tracks whether the engine is paused; jobs await entry into this gate before
/// starting.  Running jobs are not affected by pause.
private actor PauseGate {
    private var paused = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func setPaused(_ value: Bool) {
        paused = value
        if !value { drainContinuations() }
    }

    func waitIfPaused() async {
        guard paused else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    private func drainContinuations() {
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume() }
    }

    /// Drain all waiters unconditionally (used on cancel).
    func drainAll() {
        paused = false
        drainContinuations()
    }
}

/// Tracks which child processes are alive so we can kill them on cancel.
private actor ProcessRegistry {
    private var entries: [UUID: Process] = [:]
    private(set) var cancelled = false

    func register(_ proc: Process, id: UUID) {
        entries[id] = proc
    }

    func unregister(id: UUID) {
        entries.removeValue(forKey: id)
    }

    /// Mark cancelled, returns the live processes to terminate.
    func cancel() -> [Process] {
        cancelled = true
        let procs = Array(entries.values)
        entries = [:]
        return procs
    }
}

// MARK: - ConversionEngine

/// Orchestrates all conversion jobs with bounded concurrency, pause/resume,
/// and cooperative cancellation. Not itself an actor: external callers (the
/// view model) call `pause()`, `resume()`, `cancel()` synchronously; internal
/// state is protected by the actor helpers above.
final class ConversionEngine: @unchecked Sendable {

    private struct JobSnapshot: Sendable {
        let job: ConversionJob
        let sourceURL: URL
        let sourceType: SourceType
        let status: JobStatus
        let filename: String
        let path: String
        let outputPath: String
    }

    // MARK: - Configuration

    let chdmanPath:   String
    let capabilities: ChdmanCapabilities
    let concurrency:  Int
    let jobs:         [ConversionJob]
    let logStore:     LogStore

    /// Called on every log line so the view model can append it to the global log.
    /// Stored as @unchecked because AppViewModel is @MainActor-isolated (safe).
    var onLogLine: ((String) -> Void)?

    // MARK: - Concurrency primitives (all actor-isolated)

    private let sema:     AsyncSemaphore
    private let gate:     PauseGate     = .init()
    private let registry: ProcessRegistry = .init()

    // MARK: - Init

    init(
        chdmanPath:   String,
        capabilities: ChdmanCapabilities,
        concurrency:  Int,
        jobs:         [ConversionJob],
        logStore:     LogStore
    ) {
        self.chdmanPath   = chdmanPath
        self.capabilities = capabilities
        self.concurrency  = max(1, concurrency)
        self.jobs         = jobs
        self.logStore     = logStore
        self.sema         = AsyncSemaphore(max(1, concurrency))
    }

    // MARK: - External controls (callable synchronously from @MainActor)

    func pause()  { Task { await gate.setPaused(true)  } }
    func resume() { Task { await gate.setPaused(false) } }

    func cancel() {
        Task {
            let procs = await registry.cancel()
            procs.forEach { $0.terminate() }
            await gate.drainAll() // wake any jobs waiting on pause so they can observe cancel
        }
    }

    // MARK: - Main run loop

    func run() async {
        let pending = await pendingJobs()

        await withTaskGroup(of: Void.self) { group in
            for job in pending {
                // Fast cancellation check before blocking on the semaphore.
                if await registry.cancelled { break }

                await sema.wait()

                // Re-check after potentially waiting.
                if await registry.cancelled {
                    await sema.signal()
                    break
                }

                // Block here if paused; already-running jobs are unaffected.
                await gate.waitIfPaused()

                if await registry.cancelled {
                    await sema.signal()
                    break
                }

                // Capture job so the task closure owns it.
                let capturedJob = job
                group.addTask { [weak self] in
                    guard let self else { return }
                    defer { Task { await self.sema.signal() } }
                    await self.processJob(capturedJob.job, snapshot: capturedJob)
                }
            }
            await group.waitForAll()
        }

        // Any jobs still pending after a cancel — mark them cancelled.
        if await registry.cancelled {
            for job in await cancellableJobs() {
                await setJobStatus(job, status: .cancelled, detail: "Cancelled")
            }
        }
    }

    // MARK: - Per-job processing

    private func processJob(_ job: ConversionJob, snapshot: JobSnapshot) async {
        let fm = FileManager.default
        let ts = { DateFormatter.timestamp.string(from: Date()) }

        // ── Already-done check ─────────────────────────────────────────────
        if fm.fileExists(atPath: snapshot.outputPath) {
            let size = (try? fm.attributesOfItem(atPath: snapshot.outputPath))?[.size] as? Int ?? 0
            if size > 0 {
                let msg = "[\(ts())] [SKIP] \(snapshot.filename) — output CHD already exists."
                await setJob(job, status: .skipped, detail: "Output exists", log: msg)
                emit(msg)
                Task { await logStore.appendGlobal(msg) }
                return
            }
            // Zero-byte artefact — delete and reconvert.
            try? fm.removeItem(atPath: snapshot.outputPath)
        }

        // ── Source existence check ─────────────────────────────────────────
        guard fm.fileExists(atPath: snapshot.path) else {
            let msg = "[\(ts())] [FAIL] \(snapshot.filename) — source file missing."
            await setJob(job, status: .failed, detail: "Source missing", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return
        }

        let startMsg = "[\(ts())] [START] \(snapshot.filename)"
        await setJob(job, status: .converting, detail: "Converting…", log: startMsg)
        emit(startMsg)
        Task { await logStore.appendGlobal(startMsg) }

        let succeeded: Bool
        switch snapshot.sourceType {
        case .iso: succeeded = await convertISO(job, snapshot: snapshot)
        case .cue: succeeded = await convertCUE(job, snapshot: snapshot)
        case .gdi: succeeded = await convertGDI(job, snapshot: snapshot)
        }

        if succeeded {
            let okMsg = "[\(ts())] [OK] \(snapshot.filename)"
            await setJob(job, status: .done, detail: "Done", log: okMsg)
            emit(okMsg)
            Task { await logStore.appendGlobal(okMsg) }
        }
        // On failure, sub-methods handle setting status and logging.
    }

    // MARK: - ISO conversion

    private func convertISO(_ job: ConversionJob, snapshot: JobSnapshot) async -> Bool {
        let ts = { DateFormatter.timestamp.string(from: Date()) }

        // Attempt 1: createdvd (preferred for ISOs)
        if capabilities.hasCreateDVD {
            if let r = await runChdman(job: job, snapshot: snapshot, args: ["createdvd", "-i", snapshot.path, "-o", snapshot.outputPath]),
               r.succeeded, chdValid(snapshot.outputPath) {
                return true
            }
            removeInvalidCHD(snapshot.outputPath)

            if !capabilities.hasCreateCD {
                let msg = "[\(ts())] [FAIL] \(snapshot.filename) — createdvd failed and createcd unavailable."
                await setJob(job, status: .failed, detail: "createdvd failed", log: msg)
                emit(msg)
                Task { await logStore.appendGlobal(msg) }
                return false
            }

            let retryMsg = "[\(ts())] [RETRY] \(snapshot.filename) — createdvd failed, trying createcd."
            await appendLog(job, text: retryMsg + "\n")
            emit(retryMsg)
            Task { await logStore.appendGlobal(retryMsg) }
        }

        // Attempt 2: createcd
        if capabilities.hasCreateCD {
            if let r = await runChdman(job: job, snapshot: snapshot, args: ["createcd", "-i", snapshot.path, "-o", snapshot.outputPath]),
               r.succeeded, chdValid(snapshot.outputPath) {
                return true
            }
            removeInvalidCHD(snapshot.outputPath)
        }

        let failMsg = "[\(ts())] [FAIL] \(snapshot.filename) — all conversion attempts failed."
        await setJob(job, status: .failed, detail: "All attempts failed", log: failMsg)
        emit(failMsg)
        Task { await logStore.appendGlobal(failMsg) }
        return false
    }

    // MARK: - CUE conversion

    private func convertCUE(_ job: ConversionJob, snapshot: JobSnapshot) async -> Bool {
        let ts = { DateFormatter.timestamp.string(from: Date()) }

        guard capabilities.hasCreateCD else {
            let msg = "[\(ts())] [FAIL] \(snapshot.filename) — createcd not available in this chdman build."
            await setJob(job, status: .failed, detail: "createcd unavailable", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return false
        }

        guard let r = await runChdman(job: job, snapshot: snapshot, args: ["createcd", "-i", snapshot.path, "-o", snapshot.outputPath]),
              r.succeeded, chdValid(snapshot.outputPath) else {
            removeInvalidCHD(snapshot.outputPath)
            let msg = "[\(ts())] [FAIL] \(snapshot.filename) — createcd failed."
            await setJob(job, status: .failed, detail: "createcd failed", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return false
        }

        // Delete sources only after confirmed success.
        if let refs = try? CueParser().referencedFiles(cueURL: snapshot.sourceURL) {
            safeDelete(snapshot.sourceURL)
            refs.forEach { safeDelete($0) }
        }
        return true
    }

    // MARK: - GDI conversion

    private func convertGDI(_ job: ConversionJob, snapshot: JobSnapshot) async -> Bool {
        let ts = { DateFormatter.timestamp.string(from: Date()) }

        guard capabilities.hasCreateCD else {
            let msg = "[\(ts())] [FAIL] \(snapshot.filename) — createcd not available in this chdman build."
            await setJob(job, status: .failed, detail: "createcd unavailable", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return false
        }

        guard let r = await runChdman(job: job, snapshot: snapshot, args: ["createcd", "-i", snapshot.path, "-o", snapshot.outputPath]),
              r.succeeded, chdValid(snapshot.outputPath) else {
            removeInvalidCHD(snapshot.outputPath)
            let msg = "[\(ts())] [FAIL] \(snapshot.filename) — createcd failed."
            await setJob(job, status: .failed, detail: "createcd failed", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return false
        }

        if let refs = try? GdiParser().referencedFiles(gdiURL: snapshot.sourceURL) {
            safeDelete(snapshot.sourceURL)
            refs.forEach { safeDelete($0) }
        }
        return true
    }

    // MARK: - chdman process runner

    /// Returns nil if the job was cancelled or the process failed to launch.
    private func runChdman(job: ConversionJob, snapshot: JobSnapshot, args: [String]) async -> ProcessResult? {
        let runner = ProcessRunner()
        let procID = UUID()

        do {
            let result = try await runner.run(
                executablePath: chdmanPath,
                arguments: args,
                lineHandler: { [weak self] line in
                    guard let self else { return }
                    await self.appendLog(job, text: line + "\n")
                },
                processCreated: { [weak self] proc in
                    guard let self else { return }
                    // Hop to a Task to call the actor method asynchronously.
                    Task { await self.registry.register(proc, id: procID) }
                },
                processEnded: { [weak self] in
                    guard let self else { return }
                    Task { await self.registry.unregister(id: procID) }
                }
            )
            return result
        } catch is CancellationError {
            let msg = "[\(DateFormatter.timestamp.string(from: Date()))] [CANCEL] \(snapshot.filename)"
            await setJob(job, status: .cancelled, detail: "Cancelled", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return nil
        } catch {
            let msg = "[\(DateFormatter.timestamp.string(from: Date()))] [FAIL] \(snapshot.filename) — launch error: \(error.localizedDescription)"
            await setJob(job, status: .failed, detail: "Launch error", log: msg)
            emit(msg)
            Task { await logStore.appendGlobal(msg) }
            return nil
        }
    }

    // MARK: - Job state helpers

    private func setJob(_ job: ConversionJob, status: JobStatus, detail: String, log text: String) async {
        await MainActor.run {
            job.status = status
            job.detail = detail
            job.appendLog(text + "\n")
        }
    }

    private func setJobStatus(_ job: ConversionJob, status: JobStatus, detail: String) async {
        await MainActor.run {
            job.status = status
            job.detail = detail
        }
    }

    private func appendLog(_ job: ConversionJob, text: String) async {
        await MainActor.run { job.appendLog(text) }
    }

    // MARK: - File helpers

    private func chdValid(_ outputPath: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: outputPath) else { return false }
        let size = (try? fm.attributesOfItem(atPath: outputPath))?[.size] as? Int ?? 0
        return size > 0
    }

    private func removeInvalidCHD(_ path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        if size == 0 { try? fm.removeItem(atPath: path) }
    }

    private func safeDelete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Log forwarding

    private func emit(_ line: String) {
        onLogLine?(line)
    }

    @MainActor
    private func snapshot(for job: ConversionJob) -> JobSnapshot {
        JobSnapshot(
            job: job,
            sourceURL: job.sourceURL,
            sourceType: job.sourceType,
            status: job.status,
            filename: job.filename,
            path: job.path,
            outputPath: job.outputPath
        )
    }

    private func pendingJobs() async -> [JobSnapshot] {
        await MainActor.run {
            jobs
                .map(snapshot(for:))
                .filter { $0.status == .pending }
        }
    }

    private func cancellableJobs() async -> [ConversionJob] {
        await MainActor.run {
            jobs.filter { $0.status == .pending || $0.status == .paused }
        }
    }
}

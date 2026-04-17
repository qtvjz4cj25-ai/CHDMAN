import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - UI state

    @Published var selectedFolder: URL?
    @Published var isRecursive: Bool = true
    @Published var jobs: [ConversionJob] = []
    @Published var parallelJobs: Int = 2
    @Published var isScanning: Bool = false
    @Published var isConverting: Bool = false
    @Published var isPaused: Bool = false
    @Published var globalLog: String = ""
    @Published var autoScrollLog: Bool = true
    @Published var conversionStartDate: Date?
    @Published var showChdmanAlert: Bool = false
    @Published var chdmanAlertMessage: String = ""
    @Published var chdmanCapabilities: ChdmanCapabilities?

    // MARK: - Persisted settings

    @AppStorage("customChdmanPath") var customChdmanPath: String = ""
    @AppStorage("deleteSourceAfterConversion") var deleteSourceAfterConversion: Bool = false
    @AppStorage("notifyOnCompletion") var notifyOnCompletion: Bool = true

    // MARK: - Computed counts / progress

    var totalCount: Int      { jobs.count }
    var doneCount: Int       { jobs.filter { $0.status == .done      }.count }
    var failedCount: Int     { jobs.filter { $0.status == .failed    }.count }
    var skippedCount: Int    { jobs.filter { $0.status == .skipped   }.count }
    var cancelledCount: Int  { jobs.filter { $0.status == .cancelled }.count }
    var convertingCount: Int { jobs.filter { $0.status == .converting }.count }

    var finishedCount: Int {
        doneCount + failedCount + skippedCount + cancelledCount
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(finishedCount) / Double(totalCount)
    }

    var estimatedTimeRemaining: String? {
        guard let start = conversionStartDate,
              isConverting,
              finishedCount > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let avgPerJob = elapsed / Double(finishedCount)
        let remaining = Int(avgPerJob * Double(totalCount - finishedCount))
        if remaining < 60 { return "\(remaining)s" }
        if remaining < 3600 { return "\(remaining / 60)m \(remaining % 60)s" }
        return "\(remaining / 3600)h \(remaining % 3600 / 60)m"
    }

    // MARK: - Button availability

    var canScan: Bool {
        selectedFolder != nil && !isScanning && !isConverting
    }
    var canClearList: Bool {
        !jobs.isEmpty && !isConverting
    }
    var canStart: Bool {
        !jobs.isEmpty && !isConverting &&
        jobs.contains(where: { $0.status == .pending })
    }
    var canPause: Bool  { isConverting && !isPaused }
    var canResume: Bool { isConverting &&  isPaused }
    var canCancel: Bool { isConverting }

    // MARK: - Private services

    private let scanner  = FolderScanner()
    private let locator  = ChdmanLocator()
    private let logStore = LogStore()

    private var engine: ConversionEngine?
    private var conversionTask: Task<Void, Never>?

    // MARK: - Folder picker

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for disc images"
        panel.prompt  = "Select"
        if panel.runModal() == .OK {
            selectedFolder = panel.url
        }
    }

    // MARK: - Scan

    func scan() async {
        guard let folder = selectedFolder else { return }
        isScanning = true
        defer { isScanning = false }

        let discovered = await scanner.scan(folder: folder, recursive: isRecursive)
        jobs = discovered

        let msg = "[\(timestamp())] Scan complete — \(discovered.count) item(s) found in \(folder.path)"
        appendGlobalLog(msg)
        Task { await logStore.appendGlobal(msg) }
    }

    // MARK: - Clear

    func clearList() {
        jobs = []
        let msg = "[\(timestamp())] List cleared."
        appendGlobalLog(msg)
    }

    // MARK: - Start conversion

    func startConversion() async {
        // Locate chdman
        let chdmanPath: String
        do {
            chdmanPath = try await locator.locate(
                customPath: customChdmanPath.isEmpty ? nil : customChdmanPath
            )
        } catch {
            chdmanAlertMessage =
                "\(error.localizedDescription)\n\nInstall chdman with:\n    brew install rom-tools"
            showChdmanAlert = true
            return
        }

        // Detect capabilities
        let caps: ChdmanCapabilities
        do {
            caps = try await locator.detectCapabilities(chdmanPath: chdmanPath)
        } catch {
            chdmanAlertMessage =
                "Failed to detect chdman capabilities: \(error.localizedDescription)"
            showChdmanAlert = true
            return
        }
        chdmanCapabilities = caps

        let capLine = "[\(timestamp())] chdman: \(chdmanPath) | createcd=\(caps.hasCreateCD) createdvd=\(caps.hasCreateDVD)"
        appendGlobalLog(capLine)

        let concurrency = min(parallelJobs, ProcessInfo.processInfo.activeProcessorCount)
        let startMsg = "[\(timestamp())] Starting conversion — concurrency=\(concurrency)"
        appendGlobalLog(startMsg)
        Task { await logStore.appendGlobal(startMsg) }

        let eng = ConversionEngine(
            chdmanPath: chdmanPath,
            capabilities: caps,
            concurrency: concurrency,
            jobs: jobs,
            logStore: logStore,
            deleteSource: deleteSourceAfterConversion
        )
        eng.onLogLine = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.appendGlobalLog(line)
            }
        }

        engine = eng
        isConverting = true
        isPaused = false
        conversionStartDate = Date()

        conversionTask = Task { [weak self] in
            await eng.run()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isConverting = false
                self.conversionStartDate = nil
                self.engine = nil
                let doneMsg = "[\(self.timestamp())] All jobs finished — \(self.doneCount) done, \(self.failedCount) failed, \(self.skippedCount) skipped."
                self.appendGlobalLog(doneMsg)
                Task { await self.logStore.appendGlobal(doneMsg) }
                if self.notifyOnCompletion {
                    self.sendCompletionNotification()
                }
            }
        }
    }

    // MARK: - Pause / Resume / Cancel

    func pauseConversion() {
        engine?.pause()
        isPaused = true
        let line = "[\(timestamp())] [PAUSE] Conversion paused — running jobs will finish."
        appendGlobalLog(line)
        Task { await logStore.appendGlobal(line) }
    }

    func resumeConversion() {
        engine?.resume()
        isPaused = false
        let line = "[\(timestamp())] [RESUME] Conversion resumed."
        appendGlobalLog(line)
        Task { await logStore.appendGlobal(line) }
    }

    func cancelConversion() {
        engine?.cancel()
        conversionTask?.cancel()
        isConverting = false
        isPaused = false
        let line = "[\(timestamp())] [CANCEL] Conversion cancelled by user."
        appendGlobalLog(line)
        Task { await logStore.appendGlobal(line) }
    }

    // MARK: - Log helpers

    func openLogFile() {
        Task {
            if let url = await logStore.logFileURL {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func appendGlobalLog(_ line: String) {
        globalLog += line + "\n"
    }

    func timestamp() -> String {
        DateFormatter.timestamp.string(from: Date())
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "CHDMAN — Batch Complete"
        content.body = "\(doneCount) done, \(failedCount) failed, \(skippedCount) skipped."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

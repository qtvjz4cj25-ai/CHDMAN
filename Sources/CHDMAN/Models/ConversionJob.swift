import Foundation

// MARK: - SourceType

enum SourceType: String, CaseIterable, Hashable, Sendable {
    case iso = "ISO"
    case cue = "CUE"
    case gdi = "GDI"
    case chd = "CHD"
}

enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case create  = "create"
    case extract = "extract"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .create:  return "Create CHD"
        case .extract: return "Extract CHD"
        }
    }

    var icon: String {
        switch self {
        case .create:  return "archivebox.fill"
        case .extract: return "archivebox.circle"
        }
    }
}

// MARK: - JobStatus

enum JobStatus: String, CaseIterable, Hashable, Sendable {
    case pending    = "Pending"
    case converting = "Converting"
    case done       = "Done"
    case failed     = "Failed"
    case skipped    = "Skipped"
    case cancelled  = "Cancelled"
    case paused     = "Paused"

    var color: String {
        switch self {
        case .pending:    return "gray"
        case .converting: return "blue"
        case .done:       return "green"
        case .failed:     return "red"
        case .skipped:    return "orange"
        case .cancelled:  return "purple"
        case .paused:     return "yellow"
        }
    }
}

// MARK: - ConversionJob

@MainActor
final class ConversionJob: ObservableObject, Identifiable {
    private static let maxLogCharacters = 50_000

    let id = UUID()
    let sourceURL: URL
    let sourceType: SourceType
    let outputURL: URL

    @Published var status: JobStatus = .pending
    @Published var detail: String = ""
    @Published var log: String = ""

    var filename: String   { sourceURL.lastPathComponent }
    var path: String       { sourceURL.path }
    var outputPath: String { outputURL.path }

    init(sourceURL: URL, sourceType: SourceType, outputURL: URL) {
        self.sourceURL  = sourceURL
        self.sourceType = sourceType
        self.outputURL  = outputURL
    }

    func appendLog(_ text: String) {
        log.appendCappedLine(text.trimmingCharacters(in: .newlines), limit: Self.maxLogCharacters)
    }
}

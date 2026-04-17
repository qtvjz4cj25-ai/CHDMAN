import Foundation

enum CompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case fast
    case balanced
    case smallest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast:
            return "Fast"
        case .balanced:
            return "Balanced"
        case .smallest:
            return "Smallest"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            return "Larger files, shorter conversion time"
        case .balanced:
            return "Use chdman defaults"
        case .smallest:
            return "Smaller files, slower conversion"
        }
    }

    func arguments(for command: String) -> [String] {
        switch (self, command) {
        case (.balanced, _):
            return []
        case (.fast, "createcd"):
            return ["--compression", "cdzl"]
        case (.fast, "createdvd"):
            return ["--compression", "zlib"]
        case (.smallest, "createcd"):
            return ["--compression", "cdlz,cdzl,cdfl", "--hunksize", "150528"]
        case (.smallest, "createdvd"):
            return ["--compression", "lzma,zlib,huff,flac", "--hunksize", "32768"]
        default:
            return []
        }
    }
}

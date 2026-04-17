import Foundation
import SwiftUI

// MARK: - DateFormatter

extension DateFormatter {
    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

// MARK: - JobStatus color + icon

extension JobStatus {
    var swiftUIColor: Color {
        switch self {
        case .pending:    return Color(nsColor: .secondaryLabelColor)
        case .converting: return .blue
        case .done:       return .green
        case .failed:     return .red
        case .skipped:    return .orange
        case .cancelled:  return .purple
        case .paused:     return Color(nsColor: .systemYellow)
        }
    }
}

// MARK: - Color.tertiary polyfill (macOS 13 compat)
// SwiftUI's `.tertiary` foreground style exists but Color.tertiary does not
// on macOS 13 — use the nsColor equivalent instead when needed.

extension Color {
    static var tertiaryLabel: Color {
        Color(nsColor: .tertiaryLabelColor)
    }
    static var quaternaryLabel: Color {
        Color(nsColor: .quaternaryLabelColor)
    }
}

// MARK: - Path truncation

extension String {
    /// Trims a filesystem path to `maxLength` characters, keeping the filename.
    ///
    ///   "/very/long/path/to/file.iso"  →  "/very/lon…/file.iso"
    func truncatedPath(maxLength: Int = 58) -> String {
        guard count > maxLength else { return self }
        let url      = URL(fileURLWithPath: self)
        let filename = url.lastPathComponent
        let ellipsis = "…/"
        let budget   = maxLength - filename.count - ellipsis.count
        guard budget > 4 else { return ellipsis + filename }
        return String(prefix(budget)) + ellipsis + filename
    }

    mutating func appendCappedLine(_ line: String, limit: Int) {
        guard limit > 0 else {
            self = ""
            return
        }

        if !isEmpty {
            append("\n")
        }
        append(line)

        guard count > limit else { return }

        let excess = count - limit
        let trimIndex = index(startIndex, offsetBy: min(excess, count))
        self = String(self[trimIndex...])

        if let newlineIndex = firstIndex(of: "\n") {
            self = String(self[index(after: newlineIndex)...])
        }
    }
}

// MARK: - NSPasteboard helper

extension NSPasteboard {
    func setString(_ string: String) {
        clearContents()
        setString(string, forType: .string)
    }
}

// MARK: - File size

extension Int {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

import Foundation

/// Describes which subcommands the installed chdman binary supports.
struct ChdmanCapabilities: Sendable {
    let hasCreateCD:  Bool
    let hasCreateDVD: Bool
    let rawHelpText:  String
}

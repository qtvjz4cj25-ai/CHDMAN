import Foundation

/// Describes which subcommands the installed chdman binary supports.
struct ChdmanCapabilities: Sendable {
    let hasCreateCD:   Bool
    let hasCreateDVD:  Bool
    let hasExtractCD:  Bool
    let hasExtractDVD: Bool
    let rawHelpText:   String
}

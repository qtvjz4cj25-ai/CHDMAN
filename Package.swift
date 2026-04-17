// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CHDMAN",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CHDMAN",
            path: "Sources/CHDMAN",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=targeted"])
            ]
        )
    ]
)

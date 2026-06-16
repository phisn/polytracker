// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolyTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PolyTracker",
            path: "Sources/PolyTracker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

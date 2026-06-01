// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlayNotch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PlayNotch",
            path: "Sources/PlayNotch",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

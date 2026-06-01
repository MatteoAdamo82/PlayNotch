// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iNotch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "iNotch",
            path: "Sources/iNotch",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

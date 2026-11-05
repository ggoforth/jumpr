// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jumpr",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "JumprCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Jumpr",
            dependencies: ["JumprCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "JumprCoreTests",
            dependencies: ["JumprCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

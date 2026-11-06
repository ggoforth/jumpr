// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jumpr",
    platforms: [.macOS(.v15)],
    dependencies: [
        // The app's only third-party code; JumprCore stays free of it.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "JumprCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Jumpr",
            dependencies: ["JumprCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // scripts/build-app.sh embeds Sparkle.framework in Jumpr.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "JumprCoreTests",
            dependencies: ["JumprCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

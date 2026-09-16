// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoUpdaterCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DuoUpdaterCore", targets: ["DuoUpdaterCore"])
    ],
    // swift-subprocess runs every child process (`Support/ChildProcess.swift`):
    // it waits on kqueue instead of parking a thread in `waitUntilExit()`.
    //
    // Both pinned exactly, like Sparkle in `App/project.yml` — `Package.resolved`
    // is gitignored, so a pin is the only thing that says which code ships.
    // swift-system is listed so the transitive `from: "1.5.0"` in
    // swift-subprocess's manifest cannot float; it is named as a target
    // dependency below only because SwiftPM warns about an unused one on every
    // build otherwise. Subprocess links it anyway.
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.0"),
        .package(url: "https://github.com/apple/swift-system", exact: "1.8.1"),
    ],
    targets: [
        .target(
            name: "DuoUpdaterCore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
        .testTarget(
            name: "DuoUpdaterCoreTests",
            dependencies: ["DuoUpdaterCore"]
        )
    ]
)

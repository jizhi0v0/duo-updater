// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DuoUpdaterCore",
    platforms: [
        .macOS(.v14)
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
            ],
            // Recipe families written as data, one `<family>.json5` per family, read
            // at runtime through `Bundle.module` (`AppRecipeIndex.dataFamilies`).
            // `.copy`, not `.process`: the directory is shipped as it is, so the
            // loader lists it by name. Every executable that reaches the index needs
            // the resulting `DuoUpdaterCore_DuoUpdaterCore.bundle` at runtime — beside
            // a command-line binary, in `Contents/Resources` of an app; see
            // `scripts/build-cli.sh` for the one install route that copies files by hand.
            resources: [.copy("Resources/Recipes")]
        ),
        .testTarget(
            name: "DuoUpdaterCoreTests",
            dependencies: ["DuoUpdaterCore"]
        )
    ]
)

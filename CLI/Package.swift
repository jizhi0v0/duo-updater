// swift-tools-version: 6.0
import PackageDescription

// The `duo` command line interface.
//
// Its own package, not a target in `DuoUpdaterCore` (which must stay a plain
// library) and not in `application-test` (whose manifest says it is deliberately
// kept out of the app — this one ships). It links the real `DuoUpdaterCore` by
// relative path so every command exercises production code, never a
// re-implementation.
//
// Split into a `DuoKit` library plus a thin `duo` executable so the sweep's
// judgment calls — the baseline's failure streaks, version-regression detection,
// the noise filters — are unit-testable. They earned that: the changelog lag
// check shipped its first draft flagging six recipes, five of which were
// behaving correctly.
//
// No external dependencies, matching the core package's deliberate stance —
// argument parsing is hand-rolled in `ArgParser.swift`.
let package = Package(
    name: "duo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../DuoUpdaterCore")
    ],
    targets: [
        .target(
            name: "DuoKit",
            dependencies: [
                .product(name: "DuoUpdaterCore", package: "DuoUpdaterCore")
            ]
        ),
        .executableTarget(name: "duo", dependencies: ["DuoKit"]),
        .testTarget(name: "DuoKitTests", dependencies: ["DuoKit"]),
    ]
)

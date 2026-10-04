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
            dependencies: ["DuoUpdaterCore"],
            // `make test-release` (ci.yml's `release` job) exists to run
            // DuoUpdaterCore optimized, the way the app ships it. The tests
            // themselves gain nothing from -O, and compiling all of them as one
            // whole-module -O task was most of that job: 10.7 of its 14 minutes
            // on CI (run 37190107638), and single-threaded, so more cores do not
            // help. Here they build like a debug target instead: -Onone, batch
            // mode, while the library keeps -O + WMO (checked in the generated
            // manifest). Clean build on a 10-core Mac, deps + library + tests:
            // 148 s, against 420 s for this target alone before. The 2026-10-02
            // Junie abort the Release job was added for still reproduces this
            // way (see JunieChangelog.swift).
            //
            // ONLY under `--build-system native`, which `make test-release`
            // passes. The default (swiftbuild) backend plans a release target's
            // outputs as whole-module whatever these flags say, then fails on a
            // clean tree with "unable to open dependencies file
            // (…/DuoUpdaterCoreTests-primary.d)" — on CI, run 37193749278.
            // Native lets swift-driver plan from the final flags. A tree that
            // had built the old way passes by accident on the stale file.
            //
            // unsafeFlags are allowed here because nothing depends on this
            // target: CLI, application-test and the app consume the library
            // product only.
            swiftSettings: [
                .unsafeFlags(
                    ["-Onone", "-no-whole-module-optimization", "-enable-batch-mode"],
                    .when(configuration: .release)
                )
            ]
        )
    ]
)

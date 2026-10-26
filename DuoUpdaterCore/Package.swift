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
    // Pinned exactly, like Sparkle in `App/project.yml`.
    //
    // swift-system is not listed. On macOS swift-subprocess imports the OS's own
    // `System` (macOS 11+), and since 1.0.1 its manifest asks for `SystemPackage`
    // only on non-Apple platforms, so naming it here was the one thing still
    // compiling it into `duo`. SwiftPM still fetches it, because that manifest
    // declares the package unconditionally; `Package.resolved` pins its revision.
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.2"),
    ],
    targets: [
        .target(
            name: "DuoUpdaterCore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
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

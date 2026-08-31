// swift-tools-version: 6.0
import PackageDescription

// Standalone harnesses that run STRICT, ON-MACHINE checks against real bundles:
// `channel-verify` (is this build classified onto the channel its recipe expects)
// and `feed-discover` (what appcast does this bundle read, and is that address
// safe to adopt). Both link the real `DuoUpdaterCore` by relative path so they
// exercise production code — `ReleaseChannel.detect()`, `VendorProbeSource`,
// `FeedDiscovery` — never a re-implementation. Kept out of the main package so
// neither ships in the app.
let package = Package(
    name: "application-test",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../DuoUpdaterCore")
    ],
    targets: [
        .executableTarget(
            name: "channel-verify",
            dependencies: [
                .product(name: "DuoUpdaterCore", package: "DuoUpdaterCore")
            ]
        ),
        .executableTarget(
            name: "feed-discover",
            dependencies: [
                .product(name: "DuoUpdaterCore", package: "DuoUpdaterCore")
            ]
        )
    ]
)

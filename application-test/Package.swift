// swift-tools-version: 6.0
import PackageDescription

// A standalone harness package for STRICT, ON-MACHINE channel verification.
// It links the real `DuoUpdaterCore` (by relative path) so it exercises the
// production `ReleaseChannel.detect()` and `VendorProbeSource` — never a
// re-implementation. Kept out of the main package so it never ships in the app.
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
        )
    ]
)

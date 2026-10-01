import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running Junie's one-click update: which installer is fetched and run, with
/// which environment, and what the row is told.
///
/// The "installer" is a bash script handed to the updater instead of the
/// download. It does to the sandbox what `install.sh` does (2026-10-02): prints
/// its lines, lays out `versions/<new>`, re-points `current`, rewrites the shim —
/// and records the environment it saw. The busy check, the signature check (the
/// bundle launcher's text, `JunieSandbox.scanner`) and the base environment are
/// injected: nothing here reads the host's process table, runs Junie or reaches
/// the network.
@Suite struct JunieUpdaterTests {

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    /// A stand-in for `install.sh` of `channel` that installs `version` signed as
    /// `signer`. `extra` runs first.
    static func installer(
        channel: String = "release", version: String = "3419.26", signer: String = "jetbrains", extra: String = ""
    ) -> Data {
        Data("""
            #!/bin/bash
            set -euo pipefail
            CHANNEL="\(channel)"
            JUNIE_BIN="$HOME/.local/bin"
            JUNIE_DATA="$HOME/.local/share/junie"
            env > "$HOME/ENV"
            \(extra)
            echo "Fetching latest version info..."
            echo "Installing Junie \(version) for macos-aarch64..."
            printf '##O#-#\\r######  50.0%%\\r########## 100.0%%\\n' >&2
            echo "Checksum verified"
            T="$JUNIE_DATA/versions/\(version)"
            mkdir -p "$T/Applications/junie.app/Contents/MacOS" "$T/Applications/junie.app/Contents/app"
            echo "\(signer)" > "$T/Applications/junie.app/Contents/MacOS/junie"
            chmod +x "$T/Applications/junie.app/Contents/MacOS/junie"
            touch "$T/Applications/junie.app/Contents/app/junie-\(channel)-\(version).jar"
            echo "\(channel)" > "$T/channel"
            cat > "$T/Applications/junie.app/Contents/Info.plist" <<PLIST
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>\(version)</string></dict></plist>
            PLIST
            ln -sfn "$T" "$JUNIE_DATA/current"
            printf '#!/bin/bash\\n# JUNIE_MANAGED_SHIM\\n# Junie CLI Shim\\n' > "$JUNIE_BIN/junie"
            echo "Installed successfully!"
            """.utf8)
    }

    /// The first-generation install this Mac has: 1543.24, ad hoc, first shim.
    static func oldInstall() throws -> JunieSandbox {
        let box = try JunieSandbox()
        try box.install("1543.24", shim: JunieSandbox.legacyShim, channelFile: nil, signer: "adhoc")
        return box
    }

    static func status(_ box: JunieSandbox) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan().first.map(box.scanner.withSignature))
        let status = await JunieTests.check().status(of: install, settings: JunieSettings(), busy: nil)
        _ = try #require(status.oneClick)
        return status
    }

    final class Fetched: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URL] = []
        func add(_ item: URL) { lock.withLock { items.append(item) } }
        var all: [URL] { lock.withLock { items } }
    }

    static func updater(
        _ box: JunieSandbox, script: Data = installer(), fetched: Fetched = Fetched(),
        busy: @escaping JunieUpdater.BusyCheck = { _ in nil }, environment: [String: String] = [:],
        settings: JunieSettings = JunieSettings()
    ) -> JunieUpdater {
        JunieUpdater(
            busy: busy, scanner: box.scanner, environment: { environment }, settings: { settings },
            fetchScript: { url in
                fetched.add(url)
                return script
            })
    }

    func seenEnvironment(_ box: JunieSandbox) -> [String: String] {
        let text = (try? String(contentsOf: box.home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    @Test func runsTheChannelsInstallerAndChecksWhatItLeft() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let lines = Lines()
        let outcome = await Self.updater(
            box, fetched: fetched,
            environment: ["HOME": "/ZZFixture-junie/elsewhere", "PATH": "/somewhere/else", "JUNIE_VERSION": "656.1",
                          "JUNIE_ONESHOT": "1", "https_proxy": "http://127.0.0.1:9"]
        ).update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "3419.26"))
        #expect(fetched.all.map(\.absoluteString) == ["https://junie.jetbrains.com/install.sh"])
        let env = seenEnvironment(box)
        // Where the scan reads, with ~/.local/bin first so no profile is edited.
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == box.home.path + "/.local/bin:" + CLIToolCommandRunner.systemPath)
        // A pin or one-shot mode from a terminal's environment would change what
        // the installer does.
        #expect(env["JUNIE_VERSION"] == nil)
        #expect(env["JUNIE_ONESHOT"] == nil)
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        // Its temporary directory is gone afterwards.
        let tmp = try #require(env["TMPDIR"])
        #expect(tmp.contains("duo-junie-"))
        #expect(!FileManager.default.fileExists(atPath: tmp))
        #expect(lines.all.contains("Installed successfully!"))
        // The installer rewrote the launcher, and the old build is still there.
        #expect(JunieScanner.shimGeneration(of: box.launcher) == .managed)
        #expect(FileManager.default.fileExists(atPath: box.data.appendingPathComponent("versions/1543.24").path))
    }

    @Test func eapRunsTheEapInstaller() async throws {
        let box = try JunieSandbox()
        try box.install("3579.2", channelFile: "eap", jarChannel: "eap")
        let install = try #require(box.scanner.scan().first)
        let status = await JunieTests.check("3612.1").status(of: install, settings: JunieSettings(), busy: nil)
        let fetched = Fetched()
        let outcome = await Self.updater(box, script: Self.installer(channel: "eap", version: "3612.1"), fetched: fetched)
            .update(status)
        #expect(outcome == .updated(version: "3612.1"))
        #expect(fetched.all.map(\.absoluteString) == ["https://junie.jetbrains.com/install-eap.sh"])
    }

    /// The build left behind must be JetBrains'. Mutation: dropping the signature
    /// guard in `verdict` reports `.updated`.
    @Test func aNewBuildNotSignedByJetBrainsIsAFailure() async throws {
        let box = try Self.oldInstall()
        let outcome = await Self.updater(box, script: Self.installer(signer: "adhoc")).update(try await Self.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "3419.26 is not signed by JetBrains (Team 2ZEFAR8TH3): adHoc")
    }

    /// Exit 0 is not proof: an installer that left the same build is a failure.
    /// Mutation: dropping the newer-build guard reports `.updated("1543.24")`.
    @Test func anInstallerThatChangedNothingIsAFailure() async throws {
        let box = try Self.oldInstall()
        let script = Data("#!/bin/bash\nCHANNEL=\"release\"\necho 'Installed successfully!'\n".utf8)
        let outcome = await Self.updater(box, script: script).update(try await Self.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "the installer finished, but Junie is still 1543.24")
    }

    @Test func aFailedInstallerSaysWhy() async throws {
        let box = try Self.oldInstall()
        let script = Self.installer(extra: """
            echo "Downloading https://example.invalid/x.zip"
            echo "ERROR: Checksum verification failed!" >&2
            exit 1
            """)
        let outcome = await Self.updater(box, script: script).update(try await Self.status(box))
        guard case .failed(let message, let output) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "Checksum verification failed!")
        #expect(output.contains("Downloading https://example.invalid/x.zip"))
        #expect(box.scanner.scan().first?.version == "1543.24")
    }

    /// Only the channel's own installer runs: an error page, or the installer of
    /// another channel, is refused before anything runs. Mutation: dropping
    /// `isInstaller` runs the EAP script on a release install.
    @Test func aScriptThatIsNotTheChannelsInstallerIsNotRun() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let ran = box.home.appendingPathComponent("RAN")
        let eap = Self.installer(channel: "eap", version: "3579.2", extra: "touch \"$HOME/RAN\"")
        let outcome = await Self.updater(box, script: eap).update(status)
        #expect(outcome == .failed(message: "https://junie.jetbrains.com/install.sh did not answer with the release installer", output: ""))
        #expect(!FileManager.default.fileExists(atPath: ran.path))
        let html = Data("<!DOCTYPE html><html>CHANNEL=\"release\"</html>".utf8)
        #expect(await Self.updater(box, script: html).update(status)
            == .failed(message: "https://junie.jetbrains.com/install.sh did not answer with the release installer", output: ""))
    }

    @Test func busyAtTheClickRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let outcome = await Self.updater(box, fetched: fetched, busy: { _ in .downloading("x.download") }).update(status)
        #expect(outcome == .busy("Junie is downloading an update (x.download)"))
        #expect(fetched.all.isEmpty)
    }

    /// Mutation: dropping the click-time settings read runs the installer.
    @Test func autoUpdateTurnedOffSinceTheCheckRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let outcome = await Self.updater(box, fetched: fetched, settings: JunieSettings(autoUpdate: false)).update(status)
        #expect(outcome == .notOffered)
        #expect(fetched.all.isEmpty)
    }

    /// Junie staged or installed an update since the check: left alone. Mutation:
    /// dropping either re-read runs the installer.
    @Test func anInstallThatMovedSinceTheCheckIsLeftAlone() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let updates = box.data.appendingPathComponent("updates")
        let zip = try box.write(updates.appendingPathComponent("u.zip"), "zip")
        try box.write(updates.appendingPathComponent("pending-update.json"), #"{"version":"3419.22","zipPath":"\#(zip.path)"}"#)
        #expect(await Self.updater(box, fetched: fetched).update(status)
            == .busy("Junie has downloaded 3419.22 and installs it the next time it starts"))
        try FileManager.default.removeItem(at: updates.appendingPathComponent("pending-update.json"))
        try box.build("3419.22", channelFile: "release")
        try box.current(box.data.appendingPathComponent("versions/3419.22").path)
        #expect(await Self.updater(box, fetched: fetched).update(status)
            == .busy("Junie is now 3419.22, not the 1543.24 that was checked"))
        #expect(fetched.all.isEmpty)
    }

    @Test func aDownloadFailureRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let updater = JunieUpdater(
            busy: { _ in nil }, scanner: box.scanner, environment: { [:] },
            fetchScript: { _ in throw JunieRelease.Failure.http(503) })
        let outcome = await updater.update(status)
        #expect(outcome == .failed(message: "could not download https://junie.jetbrains.com/install.sh: http(503)", output: ""))
    }

    @Test func noOneClickNoRun() async throws {
        let box = try Self.oldInstall()
        let install = try #require(box.scanner.scan().first)
        let status = await JunieTests.check().status(of: install, settings: JunieSettings(autoUpdate: false), busy: nil)
        let fetched = Fetched()
        #expect(await Self.updater(box, fetched: fetched).update(status) == .notOffered)
        #expect(fetched.all.isEmpty)
    }

    @Test func installerRecognition() {
        #expect(JunieUpdater.isInstaller(Self.installer(), channel: "release"))
        #expect(!JunieUpdater.isInstaller(Self.installer(), channel: "eap"))
        #expect(!JunieUpdater.isInstaller(Data("#!/bin/bash\n# CHANNEL=\"release\"\n".utf8), channel: "release"))
    }
}

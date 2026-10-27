import Foundation
import Testing
@testable import DuoUpdaterCore

/// Each adapter's D15 plan (`ManagerAdapter.interruption`) against the writes
/// its vendor's command was measured making when stopped partway
/// (plans/cli-managers-redesign.md §13.4, 2026-10-27): a scratch home is laid
/// out as before the run, the plan's snapshot taken, the measured mid-run
/// state written over it, and `restore` must give back every byte of the
/// home. Nothing runs a vendor's command here; the writes are the ones the
/// measurement saw, by path.
///
/// Mutation for each: drop any one path or `created` rule from the plan —
/// every one of them is written by its test's mid-run state, so each such
/// drop fails (round 1 of #1722's review found six that did not).
struct ManagedInterruptionTests {

    private let home: String

    init() throws {
        let base = NSTemporaryDirectory() + "managed-interruption-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        home = (base as NSString).resolvingSymlinksInPath
    }

    private var homeURL: URL { URL(fileURLWithPath: home) }

    private func write(_ relative: String, _ text: String) throws {
        let path = home + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: path)
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    private func link(_ relative: String, to target: String) throws {
        let path = home + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    private func remove(_ relative: String) throws {
        try FileManager.default.removeItem(atPath: home + "/" + relative)
    }

    private func listing() -> [String: String] {
        var out: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(atPath: home)
        while let relative = enumerator?.nextObject() as? String {
            let path = home + "/" + relative
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                out[relative] = "-> " + target
            } else if let data = FileManager.default.contents(atPath: path) {
                out[relative] = String(decoding: data, as: UTF8.self)
            } else {
                out[relative] = "dir"
            }
        }
        return out
    }

    /// Snapshot by `plan`, apply `midRun`, restore: the home as it was.
    private func expectPutBack(
        _ plan: ManagedInterruption?, sourceLocation: SourceLocation = #_sourceLocation, midRun: () throws -> Void
    ) throws {
        defer { try? FileManager.default.removeItem(atPath: home) }
        let plan = try #require(plan, sourceLocation: sourceLocation)
        let before = listing()
        let snapshot = try ManagedSnapshot.take(plan.paths, created: plan.created)
        try midRun()
        #expect(listing() != before, "the mid-run writes changed nothing", sourceLocation: sourceLocation)
        #expect(snapshot.restore() == [], sourceLocation: sourceLocation)
        snapshot.discard()
        let after = listing()
        for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
            Issue.record("\(key): \(before[key] ?? "absent") before, \(after[key] ?? "absent") after", sourceLocation: sourceLocation)
        }
    }

    private func item(_ descriptor: ManagerDescriptor, root: String, key: String, installPath: String) -> ManagedItem {
        ManagedItem(descriptor: descriptor, root: root, key: key, name: key, installPath: installPath, shape: .package, installed: "1")
    }

    private func root(_ manager: ManagerID, _ path: String) -> ManagedRoot {
        ManagedRoot(manager: manager, path: path, binary: nil)
    }

    /// go: the binary renamed into `GOBIN` (k3: stopped after the rename).
    @Test func goPutsTheBinaryBack() throws {
        try write("go/bin/gofumpt", "v0.9.1")
        try write("go/bin/govulncheck", "v1.3.0")
        let adapter = GoAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/go/bin", key: "mvdan.cc/gofumpt", installPath: home + "/go/bin/gofumpt"),
            root: root(adapter.descriptor.id, home + "/go/bin"))
        #expect(plan?.scratchVariables == ["TMPDIR"])
        try expectPutBack(plan) {
            try write("go/bin/gofumpt", "v0.12.0")
        }
    }

    /// cargo: the binary and both records rewritten, the staging directory
    /// left holding the new binary (c6: 0.03 s after "Finished"), and a
    /// binary name the newer version adds (left behind, no package would
    /// claim it, and cargo would refuse every later install of tokei).
    /// Mutation: only `cargo-install*` new entries (`bin/tokei-extra` stays).
    @Test func cargoPutsTheBinariesRecordsAndStagingBack() throws {
        try write(".cargo/.crates.toml", """
            [v1]
            "tokei 14.0.0 (registry+https://github.com/rust-lang/crates.io-index)" = ["tokei"]

            """)
        try write(".cargo/.crates2.json", #"{"installs":{"tokei 14.0.0 (registry+https://github.com/rust-lang/crates.io-index)":{"version_req":"=14.0.0","bins":["tokei"],"features":["yaml"],"all_features":false,"no_default_features":false,"profile":"release","target":"aarch64-apple-darwin","rustc":"rustc 1.99.1"}}}"#)
        try write(".cargo/bin/tokei", "14.0.0")
        try link(".cargo/bin/cargo", to: "rustup")
        let adapter = CargoAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/.cargo", key: "tokei", installPath: home + "/.cargo/bin/tokei"),
            root: root(adapter.descriptor.id, home + "/.cargo"))
        try expectPutBack(plan) {
            try write(".cargo/bin/cargo-installH2vysO/tokei", "15.0.0")
            try write(".cargo/bin/tokei", "15.0.0")
            try write(".cargo/bin/tokei-extra", "15.0.0")
            try write(".cargo/.crates.toml", "[v1]\n\"tokei 15.0.0 (…)\" = [\"tokei\"]\n")
            try write(".cargo/.crates2.json", "{}")
        }
    }

    /// uv tool: the venv changed in place (u3: new `bin/ruff`, the old
    /// dist-info gone, a `.tmp` in the new one) and a new entry point linked.
    @Test func uvToolPutsTheVenvAndItsLinksBack() throws {
        let venv = home + "/.local/share/uv/tools/ruff"
        try write(".local/share/uv/tools/ruff/uv-receipt.toml", "ruff 0.6.0")
        try write(".local/share/uv/tools/ruff/bin/ruff", "0.6.0")
        try write(".local/share/uv/tools/ruff/lib/python3.12/site-packages/ruff-0.6.0.dist-info/METADATA", "0.6.0")
        try link(".local/bin/ruff", to: venv + "/bin/ruff")
        try write(".local/bin/other", "someone else's")
        let adapter = UvToolAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/.local/share/uv/tools", key: "ruff", installPath: venv),
            root: root(adapter.descriptor.id, home + "/.local/share/uv/tools"))
        try expectPutBack(plan) {
            try write(".local/share/uv/tools/ruff/bin/ruff", "0.17.3")
            try remove(".local/share/uv/tools/ruff/lib/python3.12/site-packages/ruff-0.6.0.dist-info")
            try write(".local/share/uv/tools/ruff/lib/python3.12/site-packages/ruff-0.17.3.dist-info/.tmpXYZ", "")
            try link(".local/bin/ruff", to: venv + "/bin/ruff-0.17.3")
            try link(".local/bin/ruff-lsp", to: venv + "/bin/ruff-lsp")
        }
    }

    /// uv python: the new patch renamed into place before either link moved
    /// (p4/p5/p7), then both links moved, and a partial download in `.temp`.
    @Test func uvPythonPutsThePatchAndLinksBack() throws {
        let dir = home + "/.local/share/uv/python"
        try write(".local/share/uv/python/cpython-3.12.5-macos-aarch64-none/bin/python3.12", "3.12.5")
        try link(".local/share/uv/python/cpython-3.12-macos-aarch64-none", to: dir + "/cpython-3.12.5-macos-aarch64-none")
        try write(".local/share/uv/python/.lock", "")
        try link(".local/bin/python3.12", to: dir + "/cpython-3.12-macos-aarch64-none/bin/python3.12")
        let adapter = UvPythonAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: dir, key: "3.12", installPath: dir + "/cpython-3.12.5-macos-aarch64-none"),
            root: root(adapter.descriptor.id, dir))
        try expectPutBack(plan) {
            try write(".local/share/uv/python/.temp/.tmpAbc/python.tar.gz", "partial")
            try write(".local/share/uv/python/cpython-3.12.15-macos-aarch64-none/bin/python3.12", "3.12.15")
            try link(".local/share/uv/python/cpython-3.12-macos-aarch64-none", to: dir + "/cpython-3.12.15-macos-aarch64-none")
            try link(".local/bin/python3.12", to: dir + "/cpython-3.12.15-macos-aarch64-none/bin/python3.12")
            try link(".local/bin/python", to: dir + "/cpython-3.12.15-macos-aarch64-none/bin/python3.12")
        }
    }

    /// pipx: a half-changed venv marked unfinished, with the old metadata
    /// (x4/x5).
    @Test func pipxPutsTheVenvAndItsAppsBack() throws {
        let venv = home + "/.local/pipx/venvs/black"
        try write(".local/pipx/venvs/black/pipx_metadata.json", #"{"main_package":{"package_version":"23.12.1"}}"#)
        try write(".local/pipx/venvs/black/bin/black", "23.12.1")
        try write(".local/pipx/shared/lib/python3.12/site-packages/pip/__init__.py", "24.0")
        try link(".local/bin/black", to: venv + "/bin/black")
        let adapter = PipxAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/.local/pipx", key: "black", installPath: venv),
            root: root(adapter.descriptor.id, home + "/.local/pipx"))
        try expectPutBack(plan) {
            try write(".local/pipx/venvs/black/pipx_unfinished", "")
            try write(".local/pipx/shared/lib/python3.12/site-packages/pip/__init__.py", "26.1")
            try remove(".local/bin/black")
            try write(".local/pipx/venvs/black/bin/black", "26.10.1")
            try link(".local/bin/blackd", to: venv + "/bin/blackd")
        }
    }

    /// mise: the new version and its links, the index, a download, the shims,
    /// and the purgatory scheduling the old version's removal (m7).
    /// Both shapes the item comes in: the scan's (the tool's directory) and
    /// the click's (`current`, from `mise ls`: the installed version's).
    @Test(arguments: ["node", "node/20.10.0"])
    func misePutsInstallsShimsAndStateBack(_ installPath: String) throws {
        let installs = home + "/.local/share/mise/installs"
        try write(".local/share/mise/installs/node/20.10.0/bin/node", "20.10.0")
        try link(".local/share/mise/installs/node/20", to: "./20.10.0")
        try write(".local/share/mise/installs/node/.mise.backend.toml", "core:node")
        try write(".local/share/mise/installs/.mise-installs.toml", "node 20.10.0")
        try write(".local/share/mise/installs/jq/1.6/bin/jq", "1.6")
        try write(".local/share/mise/shims/node", "shim")
        try write(".local/state/mise/tool-purgatory.json", "{}")
        let adapter = MiseToolsAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/.local/share/mise", key: "node", installPath: installs + "/" + installPath),
            root: root(adapter.descriptor.id, home + "/.local/share/mise"))
        try expectPutBack(plan) {
            try write(".local/share/mise/downloads/node/20.20.2/node.tar.xz", "partial")
            try write(".local/share/mise/installs/node/20.20.2/bin/node", "20.20.2")
            try link(".local/share/mise/installs/node/20", to: "./20.20.2")
            try link(".local/share/mise/installs/node/20.20", to: "./20.20.2")
            try write(".local/share/mise/installs/.mise-installs.toml", "node 20.20.2")
            try write(".local/share/mise/shims/npx", "shim")
            try write(".local/state/mise/tool-purgatory.json", #"{"node@20.10.0":"2026-10-28"}"#)
            try write(".local/state/mise/incomplete-installs/node-20.20.2", "")
        }
    }

    /// nvm: the new version moved in without the old globals (i4/i5, the
    /// latter exit 0), its download's lock left behind (i3), `lts/*` rewritten.
    @Test func nvmPutsTheVersionAliasesAndLockBack() throws {
        try write(".nvm/versions/node/v22.21.1/bin/node", "22.21.1")
        try write(".nvm/versions/node/v22.21.1/lib/node_modules/cowsay/package.json", "cowsay")
        try write(".nvm/alias/default", "22.21.1")
        try write(".nvm/alias/lts/jod", "v22.21.1")
        try write(".nvm/nvm.sh", "nvm")
        let adapter = NvmNodeAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/.nvm", key: "v22", installPath: home + "/.nvm/versions/node/v22.21.1"),
            root: root(adapter.descriptor.id, home + "/.nvm"))
        #expect(plan?.scratchVariables == ["TMPDIR"])
        try expectPutBack(plan) {
            try write(".nvm/.cache/locks/v22.23.4", "")
            try write(".nvm/versions/node/v22.23.4/bin/node", "22.23.4")
            try write(".nvm/alias/lts/jod", "v22.23.4")
        }
    }

    /// fnm: the download left in `.downloads/.tmp<random>` (i3/i4/i7), or the
    /// version renamed in whole (i6).
    @Test func fnmPutsTheVersionAndDownloadsBack() throws {
        let fnm = ".local/share/fnm"
        try write(fnm + "/node-versions/v22.21.1/installation/bin/node", "22.21.1")
        try link(fnm + "/aliases/default", to: home + "/" + fnm + "/node-versions/v22.21.1/installation")
        let adapter = FnmNodeAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/" + fnm, key: "v22", installPath: home + "/" + fnm + "/node-versions/v22.21.1"),
            root: root(adapter.descriptor.id, home + "/" + fnm))
        try expectPutBack(plan) {
            try write(fnm + "/node-versions/.downloads/.tmpBsqfdi/node/bin/node", "partial")
            try write(fnm + "/node-versions/v22.23.4/installation/bin/node", "22.23.4")
            try link(fnm + "/aliases/default", to: home + "/" + fnm + "/node-versions/v22.23.4/installation")
        }
    }

    /// pyenv and rbenv: the new version, the shims rehashed with the lock
    /// still there, the global `version` (rehash i6/i5).
    @Test(arguments: ["pyenv", "rbenv"])
    func buildManagersPutTheVersionShimsAndLockBack(_ manager: String) throws {
        let dir = manager == "pyenv" ? ".pyenv" : ".rbenv"
        let lock = manager == "pyenv" ? ".pyenv-shim" : ".rbenv-shim"
        try write(dir + "/versions/3.12.15/bin/python3", "old")
        try write(dir + "/shims/python3", "shim")
        try write(dir + "/version", "3.12.15")
        let adapter: any ManagerAdapter = manager == "pyenv" ? PyenvAdapter(home: homeURL) : RbenvAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/" + dir, key: "3.12", installPath: home + "/" + dir + "/versions/3.12.15"),
            root: root(adapter.descriptor.id, home + "/" + dir))
        #expect(plan?.scratchVariables == ["TMPDIR"])
        try expectPutBack(plan) {
            try write(dir + "/versions/3.12.16/bin/python3", "new")
            try write(dir + "/shims/" + lock, "")
            try write(dir + "/shims/python3.12", "shim")
            try write(dir + "/version", "3.12.16")
        }
    }

    /// Which installs a python upgrade may reinstall: by the backend the
    /// index records, and every directory the index does not account for;
    /// not a tool of another backend. Mutations: unrecorded directories left
    /// out (`mystery`), every directory taken (`node`), `pypi:` not read as
    /// pipx (`yamllint`).
    @Test func misePipxInstallsComeFromTheIndex() throws {
        let installs = home + "/.local/share/mise/installs"
        for name in ["node", "yamllint", "pipx-black", "mystery"] {
            try write(".local/share/mise/installs/\(name)/1/bin/x", name)
        }
        try write(".local/share/mise/installs/.mise-installs.toml", """
            [node]
            short = "node"
            full = "core:node"

            [yamllint]
            short = "yamllint"
            full = "pypi:yamllint"

            [pipx-black]
            short = "pipx:black"
            full = "pipx:black"

            """)
        #expect(MiseToolsAdapter.pipxInstalls(in: installs) == ["mystery", "pipx-black", "yamllint"])
    }

    /// mise, upgrading python: then it reinstalls every tool whose backend is
    /// pipx against the new Python (`PIPXBackend::reinstall_all`): `pipx:`,
    /// `pypi:`, and a registry shorthand such as `yamllint`, whose resolved
    /// backend only the installs index records — and may rewrite the
    /// global lockfiles — `mise.lock`, and `mise.<env>.lock` under `MISE_ENV`
    /// — through a `.mise.lock.<random>` temp file beside them. A stop in
    /// that step leaves them half done. Mutations: no pipx tools (each keeps
    /// the new text), a recorded `pypi:` backend not taken (`yamllint` keeps
    /// it), no `mise.<env>.lock` (it keeps the new text), no `.mise.lock.`
    /// rule (the temp file stays).
    @Test func misePythonPutsThePipxToolsAndLockfileBack() throws {
        let installs = home + "/.local/share/mise/installs"
        try write(".local/share/mise/installs/python/3.12.5/bin/python3", "3.12.5")
        try write(".local/share/mise/installs/pipx-black/23.12.1/bin/black", "on 3.12.5")
        try write(".local/share/mise/installs/pypi-ruff/0.15.2/bin/ruff", "on 3.12.5")
        try write(".local/share/mise/installs/yamllint/1.37.1/bin/yamllint", "on 3.12.5")
        try write(".local/share/mise/installs/.mise-installs.toml", """
            [python]
            short = "python"
            full = "core:python"
            explicit_backend = true

            [yamllint]
            short = "yamllint"
            full = "pypi:yamllint"
            explicit_backend = false

            """)
        try write(".config/mise/config.toml", "[tools]\npython = \"3.12\"\nyamllint = \"latest\"\n")
        try write(".config/mise/mise.work.lock", "python 3.12.5")
        let adapter = MiseToolsAdapter(home: homeURL)
        let plan = adapter.interruption(
            item(adapter.descriptor, root: home + "/.local/share/mise", key: "python", installPath: installs + "/python/3.12.5"),
            root: root(adapter.descriptor.id, home + "/.local/share/mise"))
        try expectPutBack(plan) {
            try write(".local/share/mise/installs/python/3.12.15/bin/python3", "3.12.15")
            try write(".local/share/mise/installs/pipx-black/23.12.1/bin/black", "on 3.12.15")
            try write(".local/share/mise/installs/pypi-ruff/0.15.2/bin/ruff", "on 3.12.15")
            try write(".local/share/mise/installs/yamllint/1.37.1/bin/yamllint", "on 3.12.15")
            try write(".config/mise/mise.lock", "python 3.12.15")
            try write(".config/mise/mise.work.lock", "python 3.12.15")
            try write(".config/mise/.mise.lock.Xk3q9a", "python 3.12.15")
        }
    }
}

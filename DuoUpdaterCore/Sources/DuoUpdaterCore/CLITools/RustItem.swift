import Foundation

/// One row of the Rust group: rustup itself, or one toolchain it keeps on a
/// channel. Identified by **where it is** — `~/.cargo/bin/rustup` for rustup, the
/// toolchain's directory under `~/.rustup/toolchains` for a toolchain.
///
/// Both rows are updated by rustup (`rustup self update`, `rustup update
/// <toolchain>`), and rustup is only ever ad hoc signed — the Intel build not
/// signed at all — so what lets DuoUpdater run it is its sha256 matching the one
/// rust-lang publishes for that version (`CLIToolTrust`, `RustRelease.identify`).
/// `trustedRustup` is that rustup as the check found it; a row without one is
/// never offered.
public struct RustItem: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        case rustup
        /// A toolchain that follows a channel (`RustToolchainName`).
        case toolchain(RustToolchainName)
    }

    /// The rustup a row's update runs, as the check proved it: byte for byte
    /// rust-lang's build of `version` for `hostTriple`.
    public struct TrustedRustup: Sendable, Equatable {
        public let path: String
        public let sha256: String
        public let version: String
        public let hostTriple: String

        public init(path: String, sha256: String, version: String, hostTriple: String) {
            self.path = path
            self.sha256 = sha256
            self.version = version
            self.hostTriple = hostTriple
        }
    }

    public let path: String
    /// rustup: the version its sha256 proved, nil when it matched no published
    /// build. A toolchain: its Rust version as its own manifest records it
    /// (`RustToolchainVersion.display`).
    public let version: String?
    public let kind: Kind
    public let trustedRustup: TrustedRustup?

    public init(path: String, version: String?, kind: Kind = .rustup, trustedRustup: TrustedRustup? = nil) {
        self.path = path
        self.version = version
        self.kind = kind
        self.trustedRustup = trustedRustup
    }
}

/// A toolchain directory's name, read with rustup's own grammar
/// (`ParsedToolchainDesc` in `src/dist/mod.rs`, rustup 1.29.1, read 2026-10-02):
///
///     ^(nightly|beta|stable|<X.Y[.Z][-beta[.N]]>)(?:-(YYYY-MM-DD))?(?:-(<target>))?$
///
/// A directory rustup installed from a channel always carries the target
/// (`stable-aarch64-apple-darwin`). Only the names that **follow** a channel are
/// kept — `stable`, `beta`, `nightly`, or `X.Y` (which moves to each `X.Y.Z`) with
/// no date. A full `X.Y.Z`, an `X.Y-beta…` or a dated name is pinned to one build
/// and `rustup update` never moves it; the user asked for those not to be shown
/// at all (2026-10-01), as for a custom toolchain (`rustup toolchain link`,
/// a symlink, which `RustScanner` skips before the name is read).
public struct RustToolchainName: Sendable, Equatable, Hashable {
    /// `stable`, `beta`, `nightly` or `X.Y` — what `channel-rust-<channel>.toml`
    /// on rust-lang's server is named after.
    public let channel: String
    public let target: String
    /// The directory name: what `rustup update` takes.
    public let name: String

    public static func parse(_ name: String) -> RustToolchainName? {
        for named in ["stable", "beta", "nightly"] where name.hasPrefix(named + "-") {
            return tracking(name, channel: named, rest: String(name.dropFirst(named.count + 1)))
        }
        // `X.Y-` with X one digit and Y 0–999 without a leading zero, as rustup
        // reads it. `1.0`–`1.8` rustup turns into `1.0.0`–`1.8.0` — pinned.
        guard let match = name.range(of: #"^[0-9]\.(?:0|[1-9][0-9]{0,2})-"#, options: .regularExpression) else {
            return nil
        }
        let channel = String(name[match].dropLast())
        if channel.hasPrefix("1."), let minor = Int(channel.dropFirst(2)), minor <= 8 { return nil }
        return tracking(name, channel: channel, rest: String(name[match.upperBound...]))
    }

    /// `rest` is what follows the channel and its `-`, kept only when it is a
    /// target and nothing else. A dated name (`nightly-2026-09-01-…`) fails that:
    /// its rest starts with a digit and has too many parts. So do `1.70-beta-…`
    /// and `1.70-beta.2-…`, which reach here as channel `1.70` with rest `beta…`.
    /// (`1.98.1-…` never does: the pattern above wants the `-` right after the
    /// minor.)
    private static func tracking(_ name: String, channel: String, rest: String) -> RustToolchainName? {
        isTarget(rest) ? RustToolchainName(channel: channel, target: rest, name: name) : nil
    }

    /// `arch-vendor-os[-env]`: three or four parts of letters, digits and `_`,
    /// the first starting with a letter and not `beta` — so `beta-aarch64-…` and
    /// `beta.2-aarch64-…` (a pinned `X.Y-beta[.N]`) are not targets.
    static func isTarget(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard (3...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }),
              let first = parts[0].first, first.isLetter, parts[0] != "beta"
        else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") } }
    }
}

/// A toolchain's Rust version as a channel manifest records it in `[pkg.rust]`:
/// `version = "1.99.0 (b940084d7 2026-09-28)"` — the release, then the commit and
/// its date, which is what `rustc -V` prints after `rustc `. Beta and nightly keep
/// one number for weeks (`1.101.0-nightly`), so only the whole label tells two
/// of their builds apart.
public struct RustToolchainVersion: Sendable, Equatable {
    /// The whole label, as written.
    public let label: String
    /// `1.99.0`, `1.100.0-beta.1`, `1.101.0-nightly`.
    public let number: String
    public let commit: String?
    public let date: String?

    public init?(label: String) {
        let text = label.trimmingCharacters(in: .whitespaces)
        guard let match = text.range(
            of: #"^([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.]+)?)(?: \(([0-9a-f]{7,40}) ([0-9]{4}-[0-9]{2}-[0-9]{2})\))?$"#,
            options: .regularExpression)
        else { return nil }
        let matched = String(text[match])
        let parts = matched.split(separator: " ", maxSplits: 1)
        number = String(parts[0])
        if parts.count == 2 {
            let inner = parts[1].dropFirst().dropLast().split(separator: " ")
            commit = String(inner[0])
            date = String(inner[1])
        } else {
            commit = nil
            date = nil
        }
        self.label = matched
    }

    /// What the row shows: the release number for a release, the whole label for
    /// a prerelease — `1.101.0-nightly` alone would read the same before and after
    /// an update.
    public var display: String { number.contains("-") ? label : number }
}

/// rustup's own setting that decides whether DuoUpdater offers its self-update:
/// `auto_self_update` in `~/.rustup/settings.toml`.
///
/// From rustup's source (`src/settings.rs`, `src/cli/self_update.rs`, 1.29.1,
/// read 2026-10-02): `auto_self_update: Option<SelfUpdateMode>`, the mode
/// `enable` | `disable` | `check-only` (kebab-case), absent meaning `enable`
/// (`SelfUpdateMode::from_cfg`). `rustup set auto-self-update <mode>` writes it.
/// `disable` and `check-only` both mean the user does not want rustup replacing
/// itself on its own, so the update is reported with `rustup self update` for
/// the user to run — even though `rustup self update` itself ignores the setting.
public struct RustupSettings: Sendable, Equatable {
    /// The raw value, nil when the key is absent.
    public var autoSelfUpdate: String?

    public init(autoSelfUpdate: String? = nil) {
        self.autoSelfUpdate = autoSelfUpdate
    }

    /// Absent or `enable`. A value rustup does not know makes rustup refuse to
    /// read the file at all; it is not taken as consent either.
    public var selfUpdateEnabled: Bool { autoSelfUpdate == nil || autoSelfUpdate == "enable" }

    /// Blocking file read: keep it off the cooperative pool.
    public static func read(rustupHome: URL) -> RustupSettings {
        guard let data = try? Data(contentsOf: rustupHome.appendingPathComponent("settings.toml")) else {
            return RustupSettings()
        }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// The top-level `auto_self_update = "…"` (either quote), before the first
    /// `[table]` — `[overrides]` follows it in the file rustup writes.
    static func parse(_ toml: String) -> RustupSettings {
        for raw in toml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard let match = line.range(
                of: #"^auto_self_update\s*=\s*(?:"([^"]*)"|'([^']*)')\s*(?:#.*)?$"#, options: .regularExpression)
            else { continue }
            let value = line[match].split(separator: "=", maxSplits: 1)[1]
                .trimmingCharacters(in: .whitespaces)
            let quote = value.first!
            let inner = value.dropFirst().prefix { $0 != quote }
            return RustupSettings(autoSelfUpdate: String(inner))
        }
        return RustupSettings()
    }
}

import Foundation

/// Finds the Sparkle appcast a bundle actually reads, and decides whether that
/// address is safe to adopt without a human first reading the feed.
///
/// **This is an authoring tool, not an update source.** Nothing on the shipping
/// check path calls it, and it must stay that way: the registry is the closed
/// set — the thing `duo verify` sweeps night after night, the thing the recipe
/// tests derive their cases from, the thing we can publish as "the apps
/// DuoUpdater supports". A discovery that adopted addresses at scan time would
/// dissolve that set into a per-machine union: two users on the same app could
/// resolve different feeds, CI would have nothing to sweep, and no human would
/// ever have read the feed that decides whether their app updates.
///
/// What this replaces is the slow, error-prone half of *writing* one of those
/// entries by hand — find the address, prove the feed belongs to this app, prove
/// its version strings live in the same namespace as the bundle's. The output is
/// a proposal for a person to commit, which is the same shape `duo triage` uses
/// for broken recipes: generate, re-check through the production code, hand it
/// over.
///
/// The gates in ``decide(_:feedItems:)`` are the whole point. Finding an address
/// is easy and not the dangerous part; every case this repo has been bitten by
/// had the *right* address and a wrong discriminator (Brave's Chromium-prefixed
/// marketing string, WeChat's four-component feed version against a
/// three-component bundle). Those are exactly what the gates refuse.
public enum FeedDiscovery {

    /// Where a candidate address came from, cheapest read first.
    public enum Origin: String, Sendable, Hashable {
        /// `Info.plist` `SUFeedURL` — the app speaking for itself. Handled apart
        /// from the others: an app that names its own feed needs no proposal,
        /// because `AppScanner` already reads this key and `SparkleAppcastSource`
        /// is already resolving it.
        case infoPlist
        /// The app's own preferences domain. Sparkle's own docs recommend the
        /// Info.plist key "even if you change it later programmatically", so a
        /// value parked here is a legitimate, if rarer, address.
        case userDefaults
        /// Recovered from the bundle's binaries. The address is in code — the
        /// case `SparkleFeedCatalog` exists for (Ghostty, OrbStack, Tailscale,
        /// Helium all keep it there).
        case binaryStrings
        /// `Contents/Resources/app-update.yml`, which electron-builder writes into
        /// every packaged app it configures an updater for ("automatically creates
        /// app-update.yml file for you on build in the resources (this file is
        /// internal)"). Being generated rather than hand-placed is what makes this
        /// family uniformly discoverable in a way Sparkle's key is not.
        case electronUpdateYAML
    }

    /// Which updater's manifest a bundle reads. The two families need different
    /// gates, because their failure shapes are different — see `decideElectron`.
    public enum Family: String, Sendable, Hashable {
        case sparkle
        case electron
    }

    /// The electron-builder config type lives in `ElectronManifest.swift`: it is
    /// read by `ElectronManifestSource` in production too, and the parsing rule
    /// (drop empty values, strip single quotes, channel defaults to `latest`) must
    /// not exist twice — a second copy is a second chance for the two to disagree
    /// about what a bundle asked for.

    public struct Candidate: Sendable, Hashable {
        /// The literal exactly as it appeared. Kept alongside `url` because `URL`
        /// percent-escapes what it cannot parse — a `%s` in a binary's format
        /// string becomes `%25s`, which then no longer looks like the template it
        /// is. Every judgement about the *shape* of an address reads this; only
        /// the fetch reads `url`.
        public let raw: String
        public let url: URL
        public let origin: Origin

        public init(raw: String, url: URL, origin: Origin) {
            self.raw = raw
            self.url = url
            self.origin = origin
        }
    }

    /// Why a candidate was not proposed for adoption. Every one of these is a
    /// "hand it to a person", never a silent drop — an unadopted app is a coverage
    /// gap someone should look at, not a resolved question.
    public enum Blocker: String, Sendable, Hashable {
        /// Nothing that looked like an appcast anywhere we know to look.
        case noCandidate
        /// Several distinct addresses, and choosing between them is a judgement
        /// about which *channel* or which *architecture* the user is on — which no
        /// rule here can make. Measured on this machine: Ghostty ships two
        /// (`release` and `tip`), Tailscale three, VLC one per architecture.
        ///
        /// Note what does NOT resolve this: asking which feed contains the
        /// installed build. A prerelease feed is normally a SUPERSET of the stable
        /// one, so four of the five multi-feed apps measured had their build in
        /// both. The fact that decides it — which train the user opted into —
        /// lives in the app's own preferences, in a different place for every app.
        case ambiguousCandidates
        /// The address answered, but nothing parsed as an appcast item.
        case feedUnparseable
        /// No item in the feed names the build that is installed, so there is no
        /// evidence this feed belongs to this app at all.
        case installedBuildNotInFeed
        /// The feed knows this build, but calls it by a marketing version the
        /// bundle does not use. **This is the Brave gate.** Brave Beta's feed says
        /// `1.95.92.0` where the installed bundle reports the Chromium-prefixed
        /// `152.1.95.92`; `VersionComparator.isNewer(_:than:)` is marketing-first,
        /// so adopting that feed compares 1 against 152 and answers "up to date"
        /// forever. WeChat fails the same gate from the other direction — its feed
        /// says `4.1.13.11` where the bundle says `4.1.13`, which compares as
        /// permanently newer: a phantom update that never clears.
        case marketingNamespaceMismatch
        /// The build matched but one side carries no marketing string, so the
        /// namespaces cannot be shown to agree. VLC's feed publishes no
        /// `sparkle:shortVersionString` at all, and build-to-build comparison
        /// happens to be right for it — but "happens to be" is what a person is for.
        case marketingUncomparable
        /// Every item in the feed carries a `<sparkle:channel>` tag, so the feed
        /// publishes no default channel. `SparkleAppcastSource.allowedChannels`
        /// always permits the untagged channel and derives nothing else for a
        /// stable user (`sparkleChannelName(.stable)` is nil), so a stable install
        /// would match **zero** items and silently never see an update. Adopting
        /// such a feed needs a `ChannelBinding` naming the tags outright
        /// (`sparkleChannelNames`, the route BetterDisplay takes). Measured on
        /// OrbStack: 3 `stable`, 3 `beta`, 1 `canary`, none untagged.
        case everyItemChannelTagged
        /// The literal is a format string, not an address — the app fills in pieces
        /// at runtime, so what is in the binary is not what it requests. OrbStack
        /// ships `https://api-updates.orbstack.dev/%s/appcast.xml?bucket=%d`: the
        /// arch, and a **rollout bucket**. (Note that address is also a different
        /// HOST from the `cdn-updates.orbstack.dev` mirror our recipe reads —
        /// whether the two agree is exactly what an audit has to settle, and a
        /// discovery run must not paper over.)
        case templatedAddress
        /// `app-update.yml` names a provider whose address it does not state.
        /// `github` gives owner/repo, `s3` a bucket — both need constructing, and
        /// Termius shows what construction is worth: its config names the private
        /// bucket `termius.desktop.autoupdate`, which does not resolve, while the
        /// address that actually answers is `autoupdate.termius.com`.
        case electronProviderNeedsConstruction
        /// The address was stated outright but did not answer with a parseable
        /// `latest-mac.yml`.
        case electronManifestUnreachable
        /// The manifest's `version` is not the version on disk. Electron carries
        /// ONE version string, so this single test does the work that takes two
        /// gates on the Sparkle side — it proves both that the manifest belongs to
        /// this app and that the strings are comparable. It also fires legitimately
        /// whenever an update is simply pending, which is exactly why it goes to a
        /// person instead of being read as "wrong manifest".
        case electronVersionMismatch
    }

    public enum Verdict: Sendable, Equatable {
        /// The bundle names its own feed. Nothing to propose — this app is
        /// already resolved by `SparkleAppcastSource` today.
        case declared(URL)
        /// The bundle names an address AND `SparkleFeedCatalog` supersedes it —
        /// the vendor abandoned that feed, and production reads the live one.
        ///
        /// Separate from `.declared` because both sentences that verdict stands
        /// for are false here: the address the `Info.plist` names is NOT what
        /// `SparkleAppcastSource` resolves, and "already covered" is exactly the
        /// reading this app class must not get — a superseding entry is the one
        /// place a declared feed is not the answer. Before `supersededFeeds`
        /// existed the two could not disagree (the fill-in table only fires when
        /// the bundle names nothing), which is why this case is new rather than
        /// missed.
        case superseded(declared: URL, live: URL)
        /// One address, and the feed proved it belongs to this bundle on both
        /// version strings. Safe to propose as a `SparkleFeedCatalog` entry.
        case adopt(URL)
        /// Found something, but a person has to decide. Carries the address when
        /// there was exactly one, so the report can name it.
        case review(Blocker, URL?)
        /// The bundle ships neither a Sparkle updater nor an electron-builder
        /// update config — not a gap, just not ours. Note what this does NOT mean:
        /// Docker Desktop publishes a perfectly good Sparkle appcast and lands
        /// here, because its own updater reads it and nothing in the bundle does.
        case noKnownUpdater
    }

    /// Everything read off one bundle, before any network call.
    public struct BundleProbe: Sendable {
        public let bundleID: String?
        /// The two version strings the gates compare against, read straight from
        /// `Info.plist`. Deliberately NOT `AppScanner`'s view: for the handful of
        /// apps where `buildVersionIsOverridden` applies, the scanner stores a
        /// number from a vendor-specific key rather than the bundle's own
        /// `CFBundleVersion`, and comparing that against a feed's `sparkle:version`
        /// is a cross-namespace read — the very thing these gates exist to catch.
        public let installed: VersionSide
        public let declaredFeed: URL?
        public let candidates: [Candidate]
        public let shipsSparkle: Bool
        public let electron: ElectronUpdateConfig?

        /// Sparkle wins a bundle that somehow has both: it is the one whose feed
        /// we can resolve through a shipping source today.
        public var family: Family? {
            if shipsSparkle { return .sparkle }
            return electron == nil ? nil : .electron
        }

        public init(
            bundleID: String?, installed: VersionSide, declaredFeed: URL?,
            candidates: [Candidate], shipsSparkle: Bool, electron: ElectronUpdateConfig? = nil
        ) {
            self.bundleID = bundleID
            self.installed = installed
            self.declaredFeed = declaredFeed
            self.candidates = candidates
            self.shipsSparkle = shipsSparkle
            self.electron = electron
        }
    }

    public struct Finding: Sendable {
        public let bundlePath: URL
        public let probe: BundleProbe
        public let verdict: Verdict
    }

    // MARK: - Phase 1: read the bundle

    /// Read one `.app` and collect every address we know how to find, without
    /// touching the network.
    public static func probe(bundleAt bundleURL: URL) -> BundleProbe {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let plist = (try? Data(contentsOf: plistURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
            as? [String: Any] ?? [:]

        let bundleID = plist["CFBundleIdentifier"] as? String
        let installed = VersionSide(
            marketing: VersionSide.plistVersionField(plist["CFBundleShortVersionString"]),
            build: VersionSide.plistVersionField(plist["CFBundleVersion"]))

        let declared = (plist["SUFeedURL"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(URL.init(string:))

        // `hasSparkleUpdater`'s test is `Contents/Frameworks/Sparkle.framework`,
        // and Helium is the standing proof that it under-reports: its copy is
        // nested inside the Chromium framework. So the flag here is a *search*,
        // not one `fileExists` — a bundle that ships Sparkle anywhere is a bundle
        // whose missing address is worth reporting.
        let shipsSparkle = declared != nil || containsSparkle(bundleURL)

        var candidates: [Candidate] = []
        if let bundleID,
           let pref = CFPreferencesCopyAppValue("SUFeedURL" as CFString, bundleID as CFString) as? String {
            let trimmed = pref.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed) {
                candidates.append(Candidate(raw: trimmed, url: url, origin: .userDefaults))
            }
        }
        for raw in appcastLiterals(inBinariesOf: bundleURL) {
            guard let url = URL(string: raw) else { continue }
            candidates.append(Candidate(raw: raw, url: url, origin: .binaryStrings))
        }

        // Same address found two ways is one candidate, not an ambiguity.
        var seen: Set<String> = []
        let deduped = candidates.filter { seen.insert($0.raw).inserted }

        let electron = ElectronUpdateConfig.read(fromBundleAt: bundleURL)

        return BundleProbe(
            bundleID: bundleID, installed: installed, declaredFeed: declared,
            candidates: deduped, shipsSparkle: shipsSparkle, electron: electron)
    }

    // MARK: - Phase 2: the gates

    /// Decide what to do with a probe, given the feed its single candidate
    /// returned. Pure — every network call happens in ``examine(bundleAt:session:)``
    /// so this stays testable against captured feeds.
    ///
    /// Gate order is load-bearing and runs cheapest-first, but more importantly
    /// each gate is a *different question*, and answering them out of order would
    /// let a later one's answer stand in for an earlier one's. "Is this our feed?"
    /// (the build match) must be settled before "do the version strings agree?",
    /// or a feed that simply doesn't know this app reads as a namespace mismatch.
    static func decide(_ probe: BundleProbe, feedItems: [SparkleAppcastItem]) -> Verdict {
        if let declared = probe.declaredFeed {
            if let live = SparkleFeedCatalog.replacement(
                forBundleID: probe.bundleID, declaredFeed: declared) {
                return .superseded(declared: declared, live: live)
            }
            return .declared(declared)
        }
        guard probe.shipsSparkle else { return .noKnownUpdater }
        guard let candidate = probe.candidates.first else {
            return .review(.noCandidate, nil)
        }
        // Templated before ambiguous, and it disqualifies the whole app rather
        // than just its own literal. A binary that builds its address at runtime
        // usually leaves several fragments behind — OrbStack's Go string table
        // yields the `%s`/`%d` form twice plus a partially-applied
        // `.../arm64/appcast.xml?bucket=` — and none of them is the address the
        // app asks for. Reporting that as "several candidates, pick one" would
        // invite exactly the wrong action.
        if let templated = probe.candidates.first(where: { isTemplated($0.raw) }) {
            return .review(.templatedAddress, templated.url)
        }
        guard probe.candidates.count == 1 else {
            return .review(.ambiguousCandidates, nil)
        }
        guard !feedItems.isEmpty else {
            return .review(.feedUnparseable, candidate.url)
        }

        // Gate 1 — does this feed account for the copy on disk? Matching on the
        // BUILD, and only the build, is deliberate: it is Sparkle's own canonical
        // key, and it is the one string that is unique per release. Marketing
        // strings collide across trains by design (a prerelease usually keeps the
        // release's `CFBundleShortVersionString`), which is precisely why
        // `SparkleAppcastSource.channel(ofInstalled:in:)` scans the build across
        // every item before it will consider marketing at all.
        guard let installedBuild = probe.installed.build else {
            return .review(.installedBuildNotInFeed, candidate.url)
        }
        guard let matched = SparkleAppcastSource.item(
            matchingInstalledBuild: installedBuild, in: feedItems)
        else {
            return .review(.installedBuildNotInFeed, candidate.url)
        }

        // Gate 2 — the Brave gate. See `Blocker.marketingNamespaceMismatch`.
        guard let feedMarketing = matched.shortVersionString?.nonEmpty,
              let installedMarketing = probe.installed.marketing
        else {
            return .review(.marketingUncomparable, candidate.url)
        }
        guard feedMarketing == installedMarketing else {
            return .review(.marketingNamespaceMismatch, candidate.url)
        }

        // Gate 3 — would a stable install match anything? See
        // `Blocker.everyItemChannelTagged`.
        guard feedItems.contains(where: { ($0.channel?.nonEmpty) == nil }) else {
            return .review(.everyItemChannelTagged, candidate.url)
        }

        return .adopt(candidate.url)
    }

    /// Probe a bundle, fetch its single candidate feed if it has one, and return
    /// the verdict. The fetch uses the same revalidating policy the production
    /// source does, so a discovery run and a real check see the same bytes.
    public static func examine(
        bundleAt bundleURL: URL, session: URLSession = .updates
    ) async -> Finding {
        let probe = probe(bundleAt: bundleURL)
        let verdict: Verdict
        switch probe.family {
        case .sparkle, nil:
            var items: [SparkleAppcastItem] = []
            if probe.declaredFeed == nil, probe.candidates.count == 1,
               !isTemplated(probe.candidates[0].raw) {
                let feed = probe.candidates[0].url
                if let data = await fetch(feed, session: session) {
                    items = SparkleAppcastParser.parse(data, relativeTo: feed)
                }
            }
            verdict = decide(probe, feedItems: items)
        case .electron:
            guard let manifest = probe.electron?.manifestURL else {
                verdict = .review(.electronProviderNeedsConstruction, nil)
                break
            }
            let body = await fetch(manifest, session: session).flatMap {
                String(data: $0, encoding: .utf8)
            }
            // The config's `channel` already names the exact macOS manifest the
            // bundle reads. electron-updater does not probe an architecture
            // sibling on Darwin, so discovery must not invent that request either.
            verdict = decideElectron(probe, manifest: manifest, body: body)
        }
        return Finding(bundlePath: bundleURL, probe: probe, verdict: verdict)
    }

    /// Decide an electron-builder bundle. Deliberately a different set of gates
    /// from the Sparkle side: electron's manifest carries ONE version string, so
    /// the whole marketing-versus-build namespace problem cannot arise, and what
    /// takes its place is whether the exact manifest declared by this bundle
    /// carries the version installed on disk.
    static func decideElectron(
        _ probe: BundleProbe, manifest: URL, body: String?
    ) -> Verdict {
        guard let body, let version = ElectronManifest.parse(body)?.version else {
            return .review(.electronManifestUnreachable, manifest)
        }
        guard version == probe.installed.marketing else {
            return .review(.electronVersionMismatch, manifest)
        }
        return .adopt(manifest)
    }

    private static func fetch(_ url: URL, session: URLSession) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    // MARK: - binary scanning

    /// Sparkle anywhere inside the bundle, at any nesting depth, under either of
    /// the two names it actually appears as.
    ///
    /// `Sparkle.framework` is the ordinary case, and nesting is why this is a walk
    /// rather than the single `fileExists` `AppScanner.hasSparkleUpdater` does:
    /// Helium's copy lives inside its Chromium framework. `Sparkle.strings` is the
    /// repackaged case — DevMate ships Sparkle *inside* `DevMateKit.framework`
    /// with no framework of its own, and The Unarchiver read as "ships no Sparkle
    /// updater" until this looked for the localizations too.
    ///
    /// Note what a false here means, because it is not "no appcast exists":
    /// Docker Desktop publishes a perfectly good Sparkle appcast and embeds no
    /// Sparkle at all — its own updater reads it. So this answers "would Sparkle
    /// be reading a feed in this bundle", which is the question that decides
    /// whether a missing address is a gap worth reporting.
    static func containsSparkle(_ bundleURL: URL) -> Bool {
        let fm = FileManager.default
        guard let e = fm.enumerator(
            at: bundleURL.appendingPathComponent("Contents"),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in e {
            let name = url.lastPathComponent
            if name == "Sparkle.framework" || name == "Sparkle.strings" { return true }
        }
        return false
    }

    /// Every appcast-shaped URL literal in the bundle's Mach-O files.
    ///
    /// Walks all of `Contents/` rather than a list of expected paths, because
    /// every guess at such a list has been wrong: VLC keeps its two
    /// per-architecture feeds in `Contents/MacOS/plugins/libmacosx_plugin.dylib`
    /// — a *subdirectory* of MacOS/, which a one-level read misses — and Helium's
    /// Sparkle (and address) live inside its Chromium framework, under a
    /// version-numbered directory rather than the conventional `Versions/A`.
    /// Membership is decided by the file's own Mach-O magic, so the walk costs a
    /// 4-byte read per file and cannot be fooled by naming.
    ///
    /// `app.asar` is included by name for Electron bundles, though note what that
    /// case taught us: ChatGPT's asar names a feed that is NOT the endpoint the
    /// app ends up asking. A literal recovered this way is a lead, never a
    /// conclusion — which is what the gates are for.
    static func appcastLiterals(inBinariesOf bundleURL: URL) -> [String] {
        let contents = bundleURL.appendingPathComponent("Contents")
        let fm = FileManager.default
        var files: [URL] = []
        if let e = fm.enumerator(
            at: contents, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                else { continue }
                if url.lastPathComponent == "app.asar" || isMachO(url) { files.append(url) }
            }
        }

        var found: [String] = []
        var seen: Set<String> = []
        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            for text in httpsLiterals(in: data) where looksLikeAppcast(text) {
                guard seen.insert(text).inserted else { continue }
                found.append(text)
            }
        }
        return found
    }

    /// Mach-O (thin or fat, either byte order) by the first four bytes. Cheaper
    /// and stricter than filtering on names or the executable bit — a bundle is
    /// full of executable scripts and of binaries with no extension at all.
    static func isMachO(_ url: URL) -> Bool {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        let magic = d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        switch magic {
        case 0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE, 0xCAFE_BABE, 0xBEBA_FECA:
            return true
        default:
            return false
        }
    }

    /// A literal the app completes at runtime is not an address. `%s`/`%d`/`%@`
    /// are the printf/NSString forms; a trailing `=`, `?` or `&` is the same
    /// thing seen from the other end — the scan stopped where the substituted
    /// value would have started. See `Blocker.templatedAddress`.
    static func isTemplated(_ text: String) -> Bool {
        if text.contains("%s") || text.contains("%d") || text.contains("%@") { return true }
        return text.hasSuffix("=") || text.hasSuffix("?") || text.hasSuffix("&")
    }

    /// A URL literal is only a candidate when it names an appcast. Kept
    /// deliberately narrow — a binary is full of https literals (telemetry, docs,
    /// support pages), and a loose filter would turn every app into an
    /// "ambiguous candidates" review that nobody can act on.
    ///
    /// KNOWN GAP, and the reason this filter can only ever be a heuristic: the
    /// exclusions below match hosts by name, and Helium rewrites Google's hosts
    /// during de-Googling — its Chromium cert URLs come through as
    /// `https://www.95tat1c.qjz9zk/cryptauthvault/v0/cert.xml`, survive the
    /// filter, and make the app read as `ambiguousCandidates` when the truthful
    /// verdict is `noCandidate`. A wrong verdict *kind* sends the reader looking
    /// for a channel decision that does not exist, so treat every candidate list
    /// as a lead. This is exactly why discovery stays an authoring tool.
    static func looksLikeAppcast(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard !lower.contains("gstatic.com"), !lower.contains("googleapis.com") else { return false }
        return lower.contains("appcast") || lower.hasSuffix(".xml")
    }

    /// Pull `https://…` ASCII runs out of a binary. Terminates a run at the first
    /// byte that cannot appear unescaped in a URL, which is what separates a
    /// literal from the string table entry that follows it.
    static func httpsLiterals(in data: Data) -> [String] {
        let needle = Array("https://".utf8)
        var out: [String] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count > needle.count else { return }
            var i = 0
            while i <= bytes.count - needle.count {
                guard bytes[i] == needle[0] else { i += 1; continue }
                var k = 1
                while k < needle.count, bytes[i + k] == needle[k] { k += 1 }
                guard k == needle.count else { i += 1; continue }
                var j = i + needle.count
                while j < bytes.count, isURLByte(bytes[j]) { j += 1 }
                if j - i > needle.count,
                   let s = String(bytes: bytes[i..<j], encoding: .utf8) {
                    out.append(s)
                }
                i = j
            }
        }
        return out
    }

    private static func isURLByte(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return "-._~:/?#[]@!$&'()*+,;=%".utf8.contains(b)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

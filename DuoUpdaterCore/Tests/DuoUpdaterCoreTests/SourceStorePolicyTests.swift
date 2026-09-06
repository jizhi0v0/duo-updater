import Testing
import Foundation
@testable import DuoUpdaterCore

/// Which sources may answer for a copy installed from the Mac App Store — as a
/// table that is executed, rather than as prose that has to be kept accurate.
///
/// **Why this exists as a test.** The same rule was learned three times, one
/// source at a time: Homebrew carried `guard !app.isMASApp` from the first
/// commit, GitHub got it 2026-08-20 (LocalSend), the vendor probe 2026-08-23
/// (WhatsApp offered 26.32.75 → 26.33.19 — the store build against the direct
/// dmg, which Update would have installed over the store copy, `_MASReceipt`
/// and sandbox entitlements included). Four sources were never revisited,
/// because each fix went where the bite was.
///
/// The prose left behind was an inventory of who carried the guard, and it went
/// wrong twice. Most recently it justified `SparkleAppcastSource`'s exemption
/// with "Keka is a store copy carrying a `SUFeedURL`" — measured, dated, and
/// false on the day it was written: `/Applications/Keka.app` is Developer
/// ID-signed with no `Contents/_MASReceipt`, and `AppScanner`'s `isMAS`
/// derivation is byte-identical then and now. That single sentence was the only
/// recorded reason not to close the hole, and it held for a week.
///
/// So: a registered reason per source, checked against what the type actually
/// declares, plus a behavioural case that runs the real `UpdateChecker`.
struct SourceStorePolicyTests {

    /// Every source in `SourceStack`, and why it may or may not answer a store
    /// copy. Registered by type name so a rename fails here rather than
    /// silently matching nothing.
    static let policy: [String: (answers: Bool, reason: String)] = [
        "MacAppStoreSource": (true,
            "it IS the store's lookup — the one place answering a store copy is the job"),
        "XcodeReleasesSource": (false,
            "gates on bundle id only, and Xcode ships on the store. Detection-only today "
            + "(downloadURL nil), so the harm would be a version readout rather than a bad "
            + "install — but 'detection-only' is a property that can change, and the point of "
            + "this gate is to stop reasoning per source"),
        "SparkleAppcastSource": (false,
            "gates on the feed URL only, so any store copy declaring SUFeedURL reached it"),
        "HomebrewCaskSource": (false,
            "a same-id cask is a different distribution with its own version scheme"),
        "GitHubReleasesSource": (false,
            "store and GitHub releases routinely sit a release apart (LocalSend)"),
        "AlcoveUpdateSource": (false,
            "a licensed vendor channel with an installable download"),
        "VendorProbeSource": (false,
            "cross-distribution installs — the WhatsApp case above"),
        "ElectronManifestSource": (false,
            "an electron-builder feed is the vendor's own distribution, not the store's"),
    ]

    /// The full stack, with Alcove present — it is omitted unless credentials
    /// exist, and a source that is absent from the array cannot be checked.
    static func fullStack() -> [any UpdateSource] {
        SourceStack.make(
            githubToken: nil,
            alcove: AlcoveUpdateSource.Credentials(licenseKey: "k", instanceID: "i"))
    }

    /// Mutation: add a source to `SourceStack` without registering it here.
    @Test func everySourceInTheStackIsRegistered() {
        let stack = Self.fullStack()
        #expect(stack.count == Self.policy.count,
                "the stack has \(stack.count) sources and the table has \(Self.policy.count)")
        for source in stack {
            let type = String(describing: Swift.type(of: source))
            #expect(Self.policy[type] != nil, """
                \(type) is in SourceStack but not registered above. Say whether it may answer \
                an App Store copy and why — the default is no, and it is the safe answer.
                """)
        }
    }

    /// The registration is a claim about the type; this is what makes it one.
    ///
    /// Mutation: flip any `answersAppStoreCopies`, or any `answers:` in the
    /// table, and this names the source.
    @Test func theRegisteredPolicyIsWhatTheTypeDeclares() {
        for source in Self.fullStack() {
            let type = String(describing: Swift.type(of: source))
            guard let entry = Self.policy[type] else { continue }  // the case above owns this
            #expect(source.answersAppStoreCopies == entry.answers,
                    "\(type) declares \(source.answersAppStoreCopies), registered as \(entry.answers)")
            #expect(!entry.reason.isEmpty)
        }
    }

    /// Exactly one source is allowed to answer, and it is the store's.
    ///
    /// Separate from the case above because that one would still pass if every
    /// source declined — an all-false table is self-consistent and useless.
    @Test func exactlyOneSourceAnswersStoreCopies() {
        let answering = Self.fullStack()
            .filter(\.answersAppStoreCopies)
            .map { String(describing: Swift.type(of: $0)) }
        #expect(answering == ["MacAppStoreSource"])
    }

    // MARK: - Behaviour, through the real checker

    /// Records whether it was asked, so "was this source consulted" is observed
    /// rather than inferred from the verdict.
    private actor Ledger {
        private(set) var asked = false
        func mark() { asked = true }
    }

    private final class Spy: UpdateSource, Sendable {
        let name: String
        let answersAppStoreCopies: Bool
        let ledger = Ledger()

        init(name: String, answersAppStoreCopies: Bool) {
            self.name = name
            self.answersAppStoreCopies = answersAppStoreCopies
        }
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            await ledger.mark()
            return RemoteVersion(shortVersion: "9.0", version: nil, downloadURL: nil,
                                 sourceName: name)
        }
    }

    private static func app(name: String, isMASApp: Bool) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: "com.example.\(name)", shortVersion: "1.0",
            buildVersion: "1", path: URL(fileURLWithPath: "/Applications/\(name).app"),
            isMASApp: isMASApp, sparkleFeedURL: URL(string: "https://example.invalid/appcast.xml"))
    }

    /// Mutation: delete the `if app.isMASApp, !source.answersAppStoreCopies`
    /// block in `UpdateChecker` and the declining spy is asked, and answers.
    @Test func aStoreCopyIsNotOfferedByANonStoreSource() async {
        let declining = Spy(name: "Elsewhere", answersAppStoreCopies: false)
        let store = Spy(name: "App Store", answersAppStoreCopies: true)
        // Declining source FIRST, so the gate is what stops it rather than the
        // store simply answering earlier. With the gate deleted this ordering is
        // what lets it win, which is exactly the WhatsApp shape.
        let checker = UpdateChecker(sources: [declining, store])
        let result = await checker.check(Self.app(name: "StoreCopy", isMASApp: true))
        #expect(await declining.ledger.asked == false, "a non-store source was consulted for a store copy")
        #expect(await store.ledger.asked)
        #expect(result.remote?.sourceName == "App Store")
    }

    /// The other direction. Without this, "the gate works" is also satisfied by
    /// a gate that declines everything, which would take every non-store app in
    /// the list down with it.
    @Test func aDirectCopyStillReachesEverySource() async {
        let declining = Spy(name: "Elsewhere", answersAppStoreCopies: false)
        let checker = UpdateChecker(sources: [declining])
        let result = await checker.check(Self.app(name: "DirectCopy", isMASApp: false))
        #expect(await declining.ledger.asked)
        #expect(result.remote?.sourceName == "Elsewhere")
    }

    /// A store copy nothing answered is "managed by the store", not "unknown" —
    /// the label the gate now produces for every row it silences.
    @Test func aStoreCopyNoSourceAnsweredReadsAsManaged() async {
        let declining = Spy(name: "Elsewhere", answersAppStoreCopies: false)
        let checker = UpdateChecker(sources: [declining])
        let result = await checker.check(Self.app(name: "StoreCopy", isMASApp: true))
        #expect(await declining.ledger.asked == false)
        #expect(result.status == .appStoreManaged)
    }
}

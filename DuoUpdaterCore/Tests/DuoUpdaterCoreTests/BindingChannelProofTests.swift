import Testing
import Foundation
@testable import DuoUpdaterCore

/// Issue #111 — `ChannelBinding` + `SparkleAppcastSource` is a third
/// install-carrying population, and neither `channelRecipesWithInstall` nor
/// `channelGitHubRulesWithInstall` can see it: both read one registry each, and
/// both `crossChannelArtifact` overloads are typed on a recipe or a rule.
///
/// What makes it worth a registry of its own rather than a note: for every app in
/// it the channel signal lives in the REQUEST — which feed URL was fetched, or
/// which header was sent — and nothing in the response corroborates it. TablePlus
/// is the sharpest case. Stable and beta come from the same host with the same
/// filename; if the vendor retires `X-Tiny-Beta-Update` a beta user is served the
/// stable dmg, with the same Team ID, notarized, past every gate we have.
@Suite struct BindingChannelProofTests {

    /// The population is derived, and it is exactly the request-keyed bindings.
    ///
    /// Pinned as an exact set rather than a count so that BOTH directions fail
    /// loudly: a new feed-swap or header-keyed binding appearing here without a
    /// proof, and an existing one quietly dropping out of the population (which
    /// would silently retire its proof rather than announce it).
    @Test func theBindingPopulationIsExactlyTheRequestKeyedOnes() {
        let needing = Set(ChannelProofRegistry.channelBindingsNeedingProof)
        #expect(needing == Set([
            ChannelProofKey("com.DanPristupov.Fork", .beta),
            ChannelProofKey("com.nssurge.surge-mac", .beta),
            ChannelProofKey("com.tinyapp.tableplus", .beta),
            ChannelProofKey("com.colliderli.iina", .beta),
            ChannelProofKey("pro.betterdisplay.BetterDisplay", .beta),
            ChannelProofKey("pro.betterdisplay.BetterDisplay", .unstable),
        ]), "the binding population changed: \(needing.map(\.description).sorted())")
        // Deduplicated: BetterDisplay reaches `.unstable` from two preference
        // combinations, and the population is a set of keys, not of routes to one.
        #expect(ChannelProofRegistry.channelBindingsNeedingProof.count == needing.count,
                "channelBindingsNeedingProof returned duplicate keys")
    }

    /// Every member of that population carries a proof, and nothing else does.
    ///
    /// The second half is the answer to issue #111's own warning that "a proof
    /// table that is half no-ops is worse than none": an entry for a channel-TAG
    /// binding would be exactly such a no-op, because `SparkleAppcastSource`
    /// already narrows the feed to the tags the user opted into, in code that runs
    /// for every such app whether or not anyone registered anything.
    @Test func bindingProofsCoverExactlyThatPopulation() {
        let needing = Set(ChannelProofRegistry.channelBindingsNeedingProof)
        for key in needing {
            #expect(ChannelProofRegistry.bindingProofs[key] != nil,
                    "\(key) can hand out an install on a channel it chose by request, and nothing states how we know the request is the right one")
        }
        for key in ChannelProofRegistry.bindingProofs.keys {
            #expect(needing.contains(key),
                    "\(key) has a binding proof but is not in the population — either it is protected some other way (making this a no-op) or the predicate stopped seeing it")
        }
    }

    /// Every registered binding anchor matches its own resolution.
    @Test func everyBindingProofMatchesItsOwnResolution() {
        for (bundleID, resolved) in ChannelBinding.allResolutions {
            let key = ChannelProofKey(bundleID, resolved.channel)
            guard ChannelProofRegistry.bindingProofs[key] != nil else { continue }
            #expect(
                RecipeSanity.crossChannelBinding(binding: resolved, bundleID: bundleID) == nil,
                "\(key): its own resolution no longer satisfies its proof")
        }
    }

    /// …and FAILS on the same binding's stable resolution.
    ///
    /// The property that makes these proofs worth having, and one the recipe-side
    /// registry cannot state as directly: an anchor is only evidence if the other
    /// channel's request would not also satisfy it. `appcast-signed-beta\.xml`
    /// proves something because `appcast-signed.xml` does not match it; an anchor
    /// of `appcast` would match both and prove nothing while looking identical in
    /// a diff. Fork is the case that makes this non-obvious — its BETA feed is the
    /// unsuffixed `feed.xml` and stable is `feed-stable.xml`, so the anchor is the
    /// absence of a suffix, and it only discriminates because `feed-stable.xml`
    /// does not contain the literal `feed.xml`.
    @Test func everyBindingProofFailsOnItsOwnStableSibling() {
        let stableByID = Dictionary(
            ChannelBinding.allResolutions
                .filter { $0.resolved.channel == .stable }
                .map { ($0.bundleID, $0.resolved) },
            uniquingKeysWith: { first, _ in first })

        for (key, proof) in ChannelProofRegistry.bindingProofs {
            guard case .recipeAnchor(let pattern, let fields) = proof else {
                Issue.record("\(key): a binding proof must be a .recipeAnchor")
                continue
            }
            // `guard`, not `try! #require`: a proof registered for a binding with
            // no enumerated stable resolution is a real (if unlikely) mistake, and
            // it should read as one failing test rather than a `fatalError` that
            // takes the whole test binary down with it.
            guard let stable = stableByID[key.bundleID] else {
                Issue.record("\(key): no stable resolution enumerated for this bundle id, so the proof cannot be shown to discriminate")
                continue
            }
            // Matched the way the guard matches it — per named field, same options.
            let matched = fields.contains { label in
                stable.channelAnchorSurface(ofField: label)?
                    .range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
            #expect(!matched,
                    "\(key): the anchor /\(pattern)/ ALSO matches this app's stable resolution, so it cannot tell the two apart and proves nothing")
        }
    }

    /// A header's value is part of the evidence, not decoration.
    ///
    /// TablePlus's server unlocks the beta feed for the literal string `true` and
    /// treats `1`/`yes` as stable, so a proof that only checked the field name
    /// would stay green through the exact vendor change that would start serving
    /// beta users stable builds. This is why `ResolvedChannel.anchorLines` renders
    /// a header as one `key: value` line: emitted as two lines, `.` could not
    /// cross between them and no anchor covering the value could ever match.
    @Test func aHeaderProofCoversTheValueNotJustTheFieldName() {
        let beta = TablePlusChannel.resolve(receiveBeta: true)
        #expect(RecipeSanity.crossChannelBinding(
            binding: beta, bundleID: TablePlusChannel.bundleID) == nil,
            "the shipping beta resolution must satisfy its own proof")

        // The vendor keeps the header but stops honouring this value — the failure
        // the registered anchor exists to catch.
        let wrongValue = ResolvedChannel(
            channel: .beta,
            feedHTTPHeaders: [TablePlusChannel.betaHeaderField: "1"])
        #expect(RecipeSanity.crossChannelBinding(
            binding: wrongValue, bundleID: TablePlusChannel.bundleID) != nil,
            "a header carrying a value the server treats as STABLE must not satisfy a beta proof")

        // …and dropping the header entirely, which is the resolution a broken
        // TablePlusChannel would produce.
        #expect(RecipeSanity.crossChannelBinding(
            binding: ResolvedChannel(channel: .beta), bundleID: TablePlusChannel.bundleID) != nil,
            "a beta resolution that sends no header at all must be complained about")
    }

    /// A binding with no proof is a finding, not a pass — the same stance the two
    /// recipe registries take, so the third population cannot be the quiet one.
    @Test func anUnregisteredBindingChannelIsAFinding() {
        let madeUp = ResolvedChannel(
            channel: .beta,
            feedOverride: URL(string: "https://example.invalid/appcast-beta.xml")!)
        #expect(RecipeSanity.crossChannelBinding(
            binding: madeUp, bundleID: "com.example.NotRegistered") != nil,
            "an unregistered binding channel must be reported, not silently allowed")

        // Stable resolutions have no other channel to cross into.
        #expect(RecipeSanity.crossChannelBinding(
            binding: ResolvedChannel(channel: .stable), bundleID: "com.example.NotRegistered") == nil,
            "a stable resolution has nothing to prove here")
    }

    /// `allResolutions` must not fall behind the resolvers it is derived from.
    ///
    /// Partial by construction and worth saying so: this catches a binding added
    /// to `boundBundleIDs` and not here (the realistic drift, since `boundBundleIDs`
    /// is what somebody already touches when adding a resolver). It cannot catch a
    /// resolver added to the `resolve` switch and to neither list — Swift offers no
    /// way to reflect over a switch's cases.
    @Test func everyBindingIsEnumerated() {
        let enumerated = Set(ChannelBinding.allResolutions.map { $0.bundleID.lowercased() })
        // Ghostty is deliberately outside `boundBundleIDs` (no user-settable
        // preference to watch) but is still a real binding, so it is enumerated.
        let expected = ChannelBinding.boundBundleIDs
            .union([GhosttyChannel.bundleID.lowercased()])
            .subtracting(ChannelBinding.vendorProbeBackedBindings)
        #expect(enumerated == expected,
                "allResolutions drifted from the resolvers: missing \(expected.subtracting(enumerated).sorted()), extra \(enumerated.subtracting(expected).sorted())")

        // `hasResolver`, not `resolve(...) != nil`: the second asks this Mac's
        // preferences, and CleanShot's resolver answers nil without a licence — so
        // this loop passed for the author and failed everywhere else, with a message
        // blaming a missing case. Same trap `allResolutions` above already avoids by
        // enumerating CleanShot through its pure resolver.
        for id in enumerated {
            #expect(ChannelBinding.hasResolver(bundleID: id),
                    "\(id) is enumerated but `resolve` has no case for it")
        }
    }

    /// The three proof maps must not collide, for the reason `githubProofs`'
    /// own doc gives: `ChannelProofKey` says nothing about which population it
    /// came from, so a shared key would be checked against the wrong one while the
    /// exhaustiveness tests all passed.
    @Test func bindingProofsDoNotCollideWithTheOtherRegistries() {
        // POPULATIONS, not just the keys somebody happened to register. A bundle
        // id that two populations could both serve on one channel is the
        // ambiguity — `ChannelProofKey` records no population, so the entry
        // written for one would be checked against the other — and it is ambiguous
        // whether or not both entries exist yet. Comparing registered keys alone
        // would pass in exactly the window where the mistake is still invisible.
        let bindingPopulation = Set(ChannelProofRegistry.channelBindingsNeedingProof)
        #expect(bindingPopulation.isDisjoint(with: Set(ChannelProofRegistry.channelRecipesWithInstall)),
                "a (bundleID, channel) is served by both the vendor recipe and binding populations")
        #expect(bindingPopulation.isDisjoint(with: Set(ChannelProofRegistry.channelGitHubRulesWithInstall)),
                "a (bundleID, channel) is served by both the GitHub rule and binding populations")
        // …and the registered maps, which is the weaker statement kept because a
        // proof can be written before its population entry exists.
        let binding = Set(ChannelProofRegistry.bindingProofs.keys)
        #expect(binding.isDisjoint(with: Set(ChannelProofRegistry.proofs.keys)),
                "a key is in both the vendor and binding proof maps")
        #expect(binding.isDisjoint(with: Set(ChannelProofRegistry.githubProofs.keys)),
                "a key is in both the GitHub and binding proof maps")
    }

    /// The `vendorProbeBackedBindings` term in the population predicate excludes
    /// nothing today, and that is measured rather than assumed.
    ///
    /// It is the one hand-written list in an otherwise derived pipeline, and its
    /// failure direction is silent narrowing — it can only REMOVE rows. Pinning
    /// its inertness means the day a binding both overrides a feed and selects a
    /// recipe, the term starts excluding something and this test says so instead
    /// of the row quietly leaving the population.
    @Test func vendorProbeBackedBindingsAreNotEnumerated() {
        let enumerated = Set(ChannelBinding.allResolutions.map { $0.bundleID.lowercased() })
        #expect(enumerated.isDisjoint(with: ChannelBinding.vendorProbeBackedBindings),
                "a vendor-probe-backed binding is now enumerated — the predicate term that excludes it has stopped being inert, so decide out loud whether its install really comes from the recipe")
    }
}

import Foundation

enum at_obdev_littlesnitch {
    static let set = AppRecipeSet(
        family: "at-obdev-littlesnitch",
        probes: [
        // History: docs/app-audits/at-obdev-littlesnitch.md#历史与实测
        // Little Snitch (Objective Development) — application-firewall / Network
        // Extension. No Sparkle feed: `SUFeedURL` is absent from both a real
        // mounted 6.4.1 (stable) and 6.5-nightly-(7301) bundle (2026-08-29). The
        // app updates itself through a bespoke component (`Little Snitch Software
        // Update.app`) that talks to a dynamic endpoint
        // (`sw-update.obdev.at/update-feeds/software-update.php`) whose request
        // shape isn't known — a plain GET answers "Malformed Request", and
        // learning the real query params needs packet capture of the running
        // client, not attempted here. The Homebrew cask (`little-snitch`) is
        // `auto_updates: true` (`brew info --cask little-snitch`), so
        // `HomebrewCaskSource` deliberately skips it — this recipe is what keeps
        // the app off `.unknown`.
        //
        // obdev separately publishes a STATIC per-major-version fallback feed at
        // `sw-update.obdev.at/update-feeds/littlesnitch6.plist` — the exact URL
        // Homebrew's own `little-snitch` cask uses in its `livecheck` block
        // (`Casks/l/little-snitch.rb`), so this is a vendor endpoint a third
        // party (Homebrew) already depends on for the same purpose, not a guess.
        // It's an XML plist ARRAY with one entry per release lifecycle
        // (`nightly`, `final`); `final` is what this recipe reads.
        //
        // VERSION SCHEME: the feed's `final` entry's `BundleVersion` is
        // byte-identical to the installed `CFBundleVersion`, and its
        // `BundleShortVersionString` matches `CFBundleShortVersionString`
        // too — so a plain marketing compare would also work for THIS entry, but
        // `versionIsBuild` is used anyway to share one comparison basis with the
        // nightly recipe below, where the feed's short-version field does NOT
        // match the installed bundle.
        //
        // `entryStartPattern` slices the two-entry array so `final`'s fields can
        // never be read out of the `nightly` entry (or vice versa) regardless of
        // which the feed happens to list first.
        //
        // No `install`: the feed states `InstallationMechanism: ReplaceBundle`
        // (a full `.app` swap, which is what `VendorInstaller` does too), but
        // Little Snitch ships a Network Extension
        // (`at.obdev.littlesnitch.networkextension.systemextension`, under
        // `Contents/Library/SystemExtensions/`) and a privileged daemon rooted at
        // `/Library/Little Snitch/`. Whether a bare `.app` swap re-activates the
        // extension as cleanly as the vendor's own updater does is NOT verified
        // on a real machine here — detection only until that's confirmed
        // end-to-end. Team `MLZF7K7B5R`.
        VendorProbeRecipe(
            bundleID: "at.obdev.littlesnitch",
            url: URL(string: "https://sw-update.obdev.at/update-feeds/littlesnitch6.plist")!,
            mode: .responseBody,
            versionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>final</string>[\s\S]*?<key>BundleVersion</key>\s*<string>(\d+)</string>"#,
            downloadURL: URL(string: "https://obdev.at/littlesnitch/download.html"),
            changelogURL: URL(string: "https://obdev.at/products/littlesnitch/releasenotes6.html"),
            versionIsBuild: true,
            displayVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>final</string>[\s\S]*?<key>BundleShortVersionString</key>\s*<string>([^<]+)</string>"#,
            // OS WINDOW: each entry states `MinimumSystemVersion` and
            // `MaximumSystemVersion`. The ceiling is how obdev says "not adapted
            // to this macOS yet", and it moves without notice (History has the
            // two readings two weeks apart), so it is read from the entry, never
            // pinned here. Issue #634.
            minimumSystemVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>final</string>[\s\S]*?<key>MinimumSystemVersion</key>\s*<string>([^<]+)</string>"#,
            maximumSystemVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>final</string>[\s\S]*?<key>MaximumSystemVersion</key>\s*<string>([^<]+)</string>"#,
            entryStartPattern: #"<key>ReleaseLifecycle</key>\s*<string>"#),

        // Little Snitch, NIGHTLY channel — same bundle id, no separate cask
        // `auto_updates` quirk to work around (the nightly cask is ALSO
        // `auto_updates: true`), and no in-app preference toggle: the 6.4.1 stable
        // bundle carried zero "nightly" strings anywhere (History has how that was
        // checked). A Nightly install is
        // a completely separate download (`little-snitch@nightly` cask, which
        // `conflicts_with` the stable cask) that happens to keep the SAME bundle id.
        //
        // CHANNEL SIGNAL: unlike every other same-bundle-id app in this
        // registry, Object Development bakes the channel word straight into the
        // installed `CFBundleShortVersionString` itself — e.g. "6.5 nightly (7301)".
        // Diffing the two Info.plists shows ONLY `CFBundleShortVersionString`
        // and `CFBundleVersion` differ; the bundle id, name and everything else
        // are identical. `ReleaseChannel.detect()` needed a new step for this
        // (see step "0.7" there): the shape is `"<num> nightly (<build>)"` —
        // space-separated with a parenthesized build suffix — not the dash-tail
        // shape (`versionTailPattern`) step 4 already recognizes, so without the
        // new rule this install would silently read as `.stable`.
        //
        // FEED-VS-BUNDLE TRAP (exactly the shape this registry's notes warn
        // about elsewhere): the feed's `BundleShortVersionString` for the
        // `nightly` entry is the bare number (e.g. "6.5") — it STRIPS the " nightly (<build>)"
        // suffix the real installed bundle carries. Never trust that field for
        // channel detection. `versionIsBuild` sidesteps it entirely by comparing
        // `BundleVersion` (e.g. "7301"), which DOES match the installed
        // `CFBundleVersion` byte-for-byte.
        //
        // Same static feed as stable, `nightly` lifecycle entry. No `install`,
        // same reasoning as the stable recipe above — and this channel is
        // explicitly the least-tested of the two by the vendor's own process.
        // No `changelogURL`: obdev's public release-notes page
        // (`releasenotes6.html`, used above) covers stable only — it has no
        // mention of "nightly" anywhere — and the per-build
        // notes endpoint the feed points at
        // (`releasenotes-legacy-swu.php?version=<build>`) is pinned to whichever
        // build this comment was written against, which would go stale the next
        // nightly ships. Leaving this nil renders the normal "no release notes"
        // state rather than a URL that quietly stops matching the version on
        // screen.
        VendorProbeRecipe(
            bundleID: "at.obdev.littlesnitch",
            url: URL(string: "https://sw-update.obdev.at/update-feeds/littlesnitch6.plist")!,
            mode: .responseBody,
            versionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>nightly</string>[\s\S]*?<key>BundleVersion</key>\s*<string>(\d+)</string>"#,
            downloadURL: URL(string: "https://obdev.at/littlesnitch/download-nightly.html"),
            versionIsBuild: true,
            displayVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>nightly</string>[\s\S]*?<key>BundleShortVersionString</key>\s*<string>([^<]+)</string>"#,
            // Same OS window as the stable recipe above, read from THIS entry.
            minimumSystemVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>nightly</string>[\s\S]*?<key>MinimumSystemVersion</key>\s*<string>([^<]+)</string>"#,
            maximumSystemVersionPattern:
                #"<key>ReleaseLifecycle</key>\s*<string>nightly</string>[\s\S]*?<key>MaximumSystemVersion</key>\s*<string>([^<]+)</string>"#,
            entryStartPattern: #"<key>ReleaseLifecycle</key>\s*<string>"#,
            channel: .nightly),
        ])
}

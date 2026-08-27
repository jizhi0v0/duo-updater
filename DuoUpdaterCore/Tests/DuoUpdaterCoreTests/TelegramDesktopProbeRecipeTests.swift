import Testing
import Foundation
@testable import DuoUpdaterCore

/// Telegram Desktop's probe reads the redirect target of the official download
/// link, which is a versioned dmg filename. Captured 2026-08-16:
/// `curl -I https://telegram.org/dl/desktop/mac` → `302`, `Location:` below.
private let telegramRedirectFixture =
    "https://td.telegram.org/tmac/tsetup.7.0.9.dmg"

/// The endpoint the app's own updater reads, kept as a fixture because it is the
/// trap this recipe deliberately avoids: versions are packed integers, not dotted
/// strings. Trimmed to the two mac keys; captured verbatim the same day.
private let telegramCurrent4Fixture = #"""
{"mac": {"alpha": {"released": "5013001005", "link": "/tmac/tmacupd{version}_{signature}"}, "beta": {"released": "6009004", "link": "/tmac/tmacupd{version}"}, "stable": {"released": "7000009", "link": "/tmac/tmacupd{version}"}}, "armac": {"stable": {"released": "7000009", "link": "/tmac/tarmacupd{version}"}}}
"""#

@Suite struct TelegramDesktopProbeRecipeTests {
    private func recipe(_ bundleID: String) -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }
    }

    @Test func readsTheDottedVersionFromTheRedirectTarget() throws {
        let recipe = try #require(self.recipe("com.tdesktop.Telegram"))
        guard case .redirectFilename = recipe.mode else {
            Issue.record("expected the redirect-filename mode"); return
        }
        // 7.0.9 is exactly what the mounted dmg reports for both
        // CFBundleShortVersionString and CFBundleVersion — no scheme mismatch.
        #expect(VendorProbeRecipe.extractVersion(
            from: telegramRedirectFixture, pattern: recipe.versionPattern) == "7.0.9")
    }

    /// The reason `current4` is not the source: it states the same release as a
    /// packed integer. A regex can only carry `7000009` forward, and nothing the
    /// installed bundle reports can be compared with that — the recipe's pattern
    /// must find nothing in it rather than latch onto a number that looks like a
    /// version.
    @Test func thePackedIntegerFeedIsNotMistakenForAVersion() throws {
        let recipe = try #require(self.recipe("com.tdesktop.Telegram"))
        #expect(VendorProbeRecipe.extractVersion(
            from: telegramCurrent4Fixture, pattern: recipe.versionPattern) == nil)
    }

    /// The MAS app (Telegram for macOS) is a different product with a different
    /// bundle id; this recipe must never claim it.
    @Test func doesNotClaimTheAppStoreTelegram() {
        #expect(recipe("ru.keepcoder.Telegram") == nil)
    }

    @Test func downloadsTheSameRedirectItProbes() throws {
        let recipe = try #require(self.recipe("com.tdesktop.Telegram"))
        let spec = try #require(recipe.install)
        guard case .redirect(let url) = spec.urlSource else {
            Issue.record("expected a redirect install source"); return
        }
        #expect(url == recipe.url)
        #expect(spec.kind == .dmg)
        // The probe must read the `Location` header, not follow it — following
        // would fetch the whole 150 MB dmg on every check.
        #expect(recipe.followRedirects == false)
    }
}

import Testing
import Foundation
@testable import DuoUpdaterCore

struct ChangelogURLPolicyTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func realVendorChangelogURLsStillPass() {
        // Sampled from the registry — the check must not cost any existing recipe
        // its notes pane.
        for s in [
            "https://www.zotero.org/support/changelog",
            "https://tailscale.com/changelog",
            "https://code.visualstudio.com/updates",
            "https://github.com/owner/repo/releases",
        ] {
            #expect(ChangelogURLPolicy.isDisplayable(url(s)), "\(s) should pass")
        }
    }

    @Test func plainHTTPIsRejected() {
        // A cleartext page can be rewritten in transit by anything on the path.
        #expect(!ChangelogURLPolicy.isDisplayable(url("http://example.com/notes")))
    }

    @Test func credentialsInTheURLAreRejected() {
        // `https://vendor.com@evil.example/` reads as the vendor at a glance.
        #expect(!ChangelogURLPolicy.isDisplayable(url("https://user:pw@evil.example/notes")))
    }

    @Test func ipLiteralHostsAreRejected() {
        #expect(!ChangelogURLPolicy.isDisplayable(url("https://192.168.1.10/notes")))
        #expect(!ChangelogURLPolicy.isDisplayable(url("https://[::1]/notes")))
    }

    @Test func aHostThatMerelyLooksNumericIsNotAnIPLiteral() {
        // Four dot-separated labels, but not a dotted quad — must still load.
        #expect(ChangelogURLPolicy.isDisplayable(url("https://1.2.3.example.com/notes")))
        #expect(!ChangelogURLPolicy.isIPLiteral("999.1.1.1"))
    }

    @Test func everyIPv4SpellingTheResolverAcceptsIsAnIPLiteral() {
        // All of these are 127.0.0.1 (or some address) to CFNetwork, and only one
        // of them has four dot-parts. The list is what `inet_aton` accepts:
        // decimal, hex, octal, and the 1-/2-/3-part shorthands.
        for host in ["2130706433", "127.1", "0x7f000001", "0177.0.0.1", "1.2.3",
                     "0x7f.1", "4294967295", "0", "192.168.1.10"] {
            #expect(ChangelogURLPolicy.isIPLiteral(host), "\(host) should be an IP literal")
        }
        // Foundation hands each spelling through `URL.host` verbatim — no
        // canonicalisation, no rejection — so the gate is the only thing between
        // the recipe and the web view.
        for s in ["https://2130706433/notes", "https://0x7f000001/", "https://127.1/",
                  "https://0177.0.0.1/", "https://1.2.3/"] {
            #expect(!ChangelogURLPolicy.isDisplayable(url(s)), "\(s) should be refused")
        }
    }

    @Test func hostnamesAreNotIPLiterals() {
        // A letter outside a hex prefix, a fifth label, an out-of-range quad, or
        // an exponent: none parses as an address, so none costs a vendor its notes.
        // The trailing-dot spelling is refused by `inet_aton` and by CFNetwork
        // alike (it goes to DNS, NSURLErrorCannotFindHost), so it is pinned as a
        // hostname here to keep the two in step.
        for host in ["chromereleases.googleblog.com", "1.2.3.example.com", "999.1.1.1",
                     "1.2.3.4.5", "1e3", "", "1.", "1..1", "127.0.0.1."] {
            #expect(!ChangelogURLPolicy.isIPLiteral(host), "\(host) should not be an IP literal")
        }
    }

    @Test func nonStandardPortsAreRejected() {
        #expect(!ChangelogURLPolicy.isDisplayable(url("https://example.com:8443/notes")))
        #expect(ChangelogURLPolicy.isDisplayable(url("https://example.com:443/notes")))
    }

    @Test func displayableReturnsNilSoCallersFallThrough() {
        #expect(ChangelogURLPolicy.displayable(nil) == nil)
        #expect(ChangelogURLPolicy.displayable(url("http://example.com")) == nil)
        #expect(ChangelogURLPolicy.displayable(url("https://example.com")) != nil)
    }

    // MARK: Derived from the registries
    //
    // Hand-written lists drift; these walk what actually ships, so a recipe added
    // later with an `http://` or credentialed URL fails here rather than silently
    // losing its notes pane in the app.

    @Test func everyVendorProbeChangelogURLPasses() {
        for recipe in VendorProbeRegistry.recipes {
            guard let url = recipe.changelogURL else { continue }
            #expect(ChangelogURLPolicy.isDisplayable(url),
                    "\(recipe.bundleID): \(url.absoluteString)")
        }
    }

    @Test func everyChangelogRecipeSourcePasses() {
        for recipe in ChangelogRecipeRegistry.recipes {
            #expect(ChangelogURLPolicy.isDisplayable(recipe.source),
                    "\(recipe.bundleID): \(recipe.source.absoluteString)")
        }
    }

    @Test func everyCatalogPagePasses() {
        for (bundleID, url) in ChangelogCatalog.pages {
            #expect(ChangelogURLPolicy.isDisplayable(url),
                    "\(bundleID): \(url.absoluteString)")
        }
    }
}

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

    @Test func reservedLocalHostnamesAreRejected() {
        for s in [
            "https://localhost/notes",
            "https://LOCALHOST./notes",
            "https://release-notes.localhost/notes",
            "https://release-notes.localhost./notes",
            "https://macbook.local/notes",
            "https://MACBOOK.LOCAL./notes",
        ] {
            #expect(!ChangelogURLPolicy.isDisplayable(url(s)), "\(s) should be refused")
        }
    }

    /// #292: the bare single-label `local` (no dot, nothing below it) had no
    /// test of its own — deleting that disjunct out of `isLocalHostname` left
    /// every other test in this file green. RFC 6762 §3 only ever discusses
    /// multi-label `single-dns-label.local.` names, so this half of the check
    /// doesn't rest on that citation; it rests on there being no public CA that
    /// issues an https certificate for an unqualified single-label name, which
    /// makes `https://local/` unreachable from anywhere legitimate regardless.
    @Test func bareLocalIsRejected() {
        for s in ["https://local/notes", "https://LOCAL./notes"] {
            #expect(!ChangelogURLPolicy.isDisplayable(url(s)), "\(s) should be refused")
        }
    }

    @Test func rejectionReasonNamesTheFailingGuard() {
        #expect(ChangelogURLPolicy.rejectionReason(url("https://example.com/notes")) == nil)
        #expect(ChangelogURLPolicy.rejectionReason(url("http://example.com/notes")) != nil)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://user:pw@example.com/notes")) != nil)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://192.168.1.10/notes")) != nil)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://local/notes")) != nil)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://macbook.local/notes")) != nil)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://example.com:8443/notes")) != nil)
    }

    /// #299: `rejectionReason` used to return a bare `String` that a caller put
    /// straight on screen — the one user-visible literal
    /// `check_localizable_keys.py` cannot see, because it never goes through
    /// `String(localized:)`. This pins the *specific* case each guard now
    /// reports, not just non-nil, so a change that reorders `RejectionReason`'s
    /// cases or has two guards collapse onto the same one is caught here.
    @Test func rejectionReasonReportsTheSpecificCategory() {
        #expect(ChangelogURLPolicy.rejectionReason(url("http://example.com/notes")) == .notHTTPS)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://user:pw@example.com/notes")) == .hasCredentials)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://192.168.1.10/notes")) == .ipLiteral)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://local/notes")) == .reservedLocalName)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://macbook.local/notes")) == .reservedLocalName)
        #expect(ChangelogURLPolicy.rejectionReason(url("https://example.com:8443/notes")) == .nonStandardPort)
    }

    /// `logToken` feeds a `Log.` line (CLAUDE.md: those stay English and stable
    /// so reports stay grep-able), `localizedDescription` feeds the on-screen
    /// blocked-notice pane. They must never be the same representation, or one
    /// audience is getting the wrong one — and every case needs both, worded
    /// distinctly, with nothing interpolated into either.
    @Test func everyReasonHasADistinctLogTokenAndLocalizedDescription() {
        let allCases: [ChangelogURLPolicy.RejectionReason] = [
            .notHTTPS, .hasCredentials, .noHost, .ipLiteral, .reservedLocalName, .nonStandardPort,
        ]
        var seenLogTokens = Set<String>()
        var seenDescriptions = Set<String>()
        for reason in allCases {
            let token = reason.logToken
            let description = reason.localizedDescription
            #expect(!token.isEmpty)
            #expect(!description.isEmpty)
            #expect(token != description, "\(reason) should word its log line and its on-screen text differently")
            #expect(seenLogTokens.insert(token).inserted, "duplicate logToken: \(token)")
            #expect(seenDescriptions.insert(description).inserted, "duplicate localizedDescription: \(description)")
        }
    }

    /// `logToken` is read out of shipped log lines and compared against past
    /// reports — see CLAUDE.md's rule that `Log.` text must stay stable. This
    /// pins the exact strings `rejectionReason` used to return directly, before
    /// #299 turned it into an enum, so a future refactor cannot silently reword
    /// them.
    @Test func logTokenTextIsUnchangedFromTheOriginalStrings() {
        #expect(ChangelogURLPolicy.RejectionReason.notHTTPS.logToken == "not an https URL")
        #expect(ChangelogURLPolicy.RejectionReason.hasCredentials.logToken == "URL carries credentials")
        #expect(ChangelogURLPolicy.RejectionReason.noHost.logToken == "URL has no host")
        #expect(ChangelogURLPolicy.RejectionReason.ipLiteral.logToken == "host is an IP literal, not a name")
        #expect(ChangelogURLPolicy.RejectionReason.reservedLocalName.logToken == "host is a reserved local-only name")
        #expect(ChangelogURLPolicy.RejectionReason.nonStandardPort.logToken == "non-standard port")
    }

    /// The whole point of `RejectionReason` being a closed enum instead of the
    /// `String` it replaced is that no case can carry the attacker/vendor-
    /// controlled host or port that triggered it. This is the regression test
    /// for that property: feed hosts and ports designed to show up if anything
    /// ever leaked into the text, on every reason `rejectionReason` can return
    /// for a URL that actually carries one.
    @Test func neitherRepresentationEverInterpolatesTheURL() {
        let needle = "tell-tale-host-should-never-appear"
        let cases: [(URL, ChangelogURLPolicy.RejectionReason)] = [
            (url("http://\(needle).example/notes"), .notHTTPS),
            (url("https://user:\(needle)@example.com/notes"), .hasCredentials),
            (url("https://192.168.1.10/notes"), .ipLiteral),
            (url("https://\(needle).local/notes"), .reservedLocalName),
            (url("https://example.com:6667/notes"), .nonStandardPort),
        ]
        for (u, expected) in cases {
            let reason = ChangelogURLPolicy.rejectionReason(u)
            #expect(reason == expected)
            #expect(reason?.logToken.contains(needle) != true)
            #expect(reason?.localizedDescription.contains(needle) != true)
            #expect(reason?.logToken.contains("6667") != true)
            #expect(reason?.localizedDescription.contains("6667") != true)
        }
    }

    /// #299: the blocked-notice pane writes a *translated* string into raw
    /// HTML — a fixed English category never needed more than `&`/`<` escaped,
    /// but a translation of it can legitimately contain any of the five
    /// characters below (French/German quoting conventions, for one). Mutating
    /// any single replacement out of `htmlEscaped` must turn one of these red.
    @Test func htmlEscapedCoversAllFiveSignificantCharacters() {
        #expect(ChangelogURLPolicy.htmlEscaped("&") == "&amp;")
        #expect(ChangelogURLPolicy.htmlEscaped("<") == "&lt;")
        #expect(ChangelogURLPolicy.htmlEscaped(">") == "&gt;")
        #expect(ChangelogURLPolicy.htmlEscaped("\"") == "&quot;")
        #expect(ChangelogURLPolicy.htmlEscaped("'") == "&#39;")
        // Ordering matters: escaping `&` first must not double-escape the
        // entities this function itself just inserted.
        #expect(ChangelogURLPolicy.htmlEscaped("<a href=\"x\">it's & done</a>")
                == "&lt;a href=&quot;x&quot;&gt;it&#39;s &amp; done&lt;/a&gt;")
        #expect(ChangelogURLPolicy.htmlEscaped("plain text") == "plain text")
    }

    @Test func localWordsInsideOrdinaryDomainsStillPass() {
        for s in [
            "https://localhost.example.com/notes",
            "https://local.example.com/notes",
            "https://notlocal.example/notes",
            "https://example.localhost.example/notes",
        ] {
            #expect(ChangelogURLPolicy.isDisplayable(url(s)), "\(s) should pass")
        }
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

    /// One appended dot used to reopen the hole in *every* spelling: WebKit drops
    /// a single trailing empty label before parsing the host, `inet_aton` does not,
    /// so `https://127.0.0.1./` passed the gate and then loaded 127.0.0.1. Measured
    /// against a listener on this machine — `curl` reported `remote_ip=127.0.0.1`
    /// for `http://127.0.0.1.:8931/`, `http://2130706433.:8931/` and
    /// `http://127.1.:8931/`, and a real `WKWebView` rewrote its own `URL` to
    /// `http://127.0.0.1:8931/` for each — while `inet_aton` rejected all three.
    @Test func aTrailingDotDoesNotLaunderAnIPLiteral() {
        for host in ["127.0.0.1.", "2130706433.", "127.1.", "0x7f000001.", "0177.0.0.1.", "1."] {
            #expect(ChangelogURLPolicy.isIPLiteral(host), "\(host) should be an IP literal")
        }
        for s in ["https://127.0.0.1./notes", "https://2130706433./", "https://127.1./"] {
            #expect(!ChangelogURLPolicy.isDisplayable(url(s)), "\(s) should be refused")
        }
        // One dot, not two. An empty label that is not last is a parse failure for
        // WebKit as well, so `1..1` is a hostname to both.
        #expect(!ChangelogURLPolicy.isIPLiteral("1..1"))
        #expect(!ChangelogURLPolicy.isIPLiteral("."))
        // A real domain keeps its notes whether or not it is spelled absolutely.
        #expect(!ChangelogURLPolicy.isIPLiteral("chromereleases.googleblog.com."))
        #expect(ChangelogURLPolicy.isDisplayable(url("https://chromereleases.googleblog.com./notes")))
    }

    /// `URL.host` strips the brackets off an IPv6 literal, so nothing in the app
    /// reaches `isIPLiteral` with one — which would leave the bracket arm of the
    /// guard untested and free to be deleted. Called directly so it is not.
    @Test func aBracketedAuthorityIsAnIPLiteralWhenHandedOverRaw() {
        #expect(ChangelogURLPolicy.isIPLiteral("[::1]"))
        #expect(ChangelogURLPolicy.isIPLiteral("[2001:db8::1]"))
        #expect(ChangelogURLPolicy.isIPLiteral("::1"))
    }

    @Test func hostnamesAreNotIPLiterals() {
        // A letter outside a hex prefix, a fifth label, an out-of-range quad, or
        // an exponent: none parses as an address, so none costs a vendor its notes.
        // (The trailing-dot spellings live in `aTrailingDotDoesNotLaunderAnIPLiteral`
        // — they ARE addresses to the web view, and this gate now says so too.)
        for host in ["chromereleases.googleblog.com", "1.2.3.example.com", "999.1.1.1",
                     "1.2.3.4.5", "1e3", "", "1..1", "0x7f000001junk"] {
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

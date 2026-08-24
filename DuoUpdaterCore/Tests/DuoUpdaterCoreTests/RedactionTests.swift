import Testing
import Foundation
@testable import DuoUpdaterCore

/// Everything an automated sweep publishes — an issue body, a model prompt, a
/// report file — passes through `Redactor` first. These tests use the real
/// shapes the app actually handles, because a redactor tested only on invented
/// strings proves nothing about the ones that matter.
@Suite struct RedactionTests {

    /// CleanShot's licensed appcast: the activation key rides in the query string
    /// of an otherwise ordinary feed URL. `CleanShotChannel`'s own file comment
    /// warns against logging this URL; this is the machine-checked version of
    /// that warning.
    @Test func cleanShotsLicensedFeedURLLosesItsKey() {
        let key = "CS-9F3A21B4C7E85D06A1F2"
        let feed = URL(string:
            "https://updates.getcleanshot.com/v3/appcast.xml?key=\(key)&os=macos")!

        let redacted = Redactor.url(feed)
        #expect(!redacted.contains(key))
        #expect(redacted.contains("updates.getcleanshot.com"))
        #expect(redacted.contains("os=macos"), "non-sensitive parameters must survive")
    }

    /// Alcove's flow: a license key posted for a bearer token, then the token in
    /// an Authorization header reused on the download.
    @Test func alcovesBearerTokenIsDroppedFromHeadersAndText() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbGNvdmUtaW5zdGFuY2UifQ.c2lnbmF0dXJl"
        let headers = [
            "Authorization": "Bearer \(jwt)",
            "User-Agent": "DuoUpdater/0.1",
        ]
        let redacted = Redactor.headers(headers)
        #expect(redacted["Authorization"] == Redactor.placeholder)
        #expect(redacted["User-Agent"] == "DuoUpdater/0.1")

        // The same token pasted into a log line or a body sample.
        #expect(!Redactor.text("failed with Bearer \(jwt)").contains(jwt))
    }

    /// A key in free text — a log line, a captured response body — not just in a
    /// parsed URL.
    @Test func secretsInFreeTextAreScrubbed() {
        let cases = [
            "GET /appcast?license_key=ABCD-1234-EFGH-5678 HTTP/1.1",
            #"{"api_key": "sk-ant-api03-abcdefghijklmnopqrstuvwxyz012345"}"#,
            "instance_id=7f3a21b4c7e85d06a1f2b3c4d5e6f708",
            "token: ghp_abcdefghijklmnopqrstuvwxyz0123456789",
        ]
        for input in cases {
            let out = Redactor.text(input)
            #expect(out.contains(Redactor.placeholder), "not redacted: \(input)")
            #expect(!out.contains("ABCD-1234-EFGH-5678"))
            #expect(!out.contains("sk-ant-api03-abcdefghijklmnopqrstuvwxyz012345"))
            #expect(!out.contains("7f3a21b4c7e85d06a1f2b3c4d5e6f708"))
            #expect(!out.contains("ghp_abcdefghijklmnopqrstuvwxyz0123456789"))
        }
    }

    /// The redactor must not eat the thing the report exists to show. A version
    /// feed's actual content — versions, filenames, dates — has to survive, or
    /// the body sample is useless for repairing a pattern.
    @Test func versionFeedContentSurvivesRedaction() {
        let body = """
        version: 8.23.0-beta.1
        files:
          - url: signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg
            size: 263191264
        releaseDate: '2026-08-05T23:09:31.413Z'
        """
        let out = Redactor.text(body)
        #expect(out.contains("8.23.0-beta.1"))
        #expect(out.contains("signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg"))
        #expect(out.contains("2026-08-05"))
    }

    @Test func inlineScriptsAreStripped() {
        let page = "<html><script>var token='abc';</script><p>Version 4.2.0</p></html>"
        let out = Redactor.text(page)
        #expect(!out.contains("var token"))
        #expect(out.contains("Version 4.2.0"))
    }

    @Test func textCanBeCapped() {
        // Deliberately not hex: a long run of `a`-`f` is itself redacted as an
        // opaque blob, which is the intended over-eagerness but would leave
        // nothing to truncate.
        let out = Redactor.text(String(repeating: "version ", count: 200), limit: 100)
        #expect(out.count < 130)
        #expect(out.hasSuffix("…[truncated]"))
    }
}

/// The invariant that keeps the sweep away from credentials in the first place:
/// no credential-bearing app may be reachable through a registry the verifier
/// iterates.
@Suite struct RegistrySecurityTests {

    /// `AlcoveUpdateSource` holds a license key and a bearer token. It is wired
    /// in by `AppListModel` only when credentials exist, and it is deliberately
    /// not an entry in any registry — so a registry sweep can never reach it.
    /// A future refactor that "tidied" it into one would silently put a bearer
    /// token in the sweep's path.
    @Test func theAuthenticatedAlcoveSourceIsInNoRegistry() {
        let alcove = AlcoveUpdateSource.bundleID
        // The public CDN mirror recipe under the same bundle id is fine and
        // expected — what must not exist is a recipe carrying the auth flow.
        for recipe in VendorProbeRegistry.recipes where recipe.bundleID == alcove {
            #expect(recipe.url.host?.contains("api.tryalcove.com") != true,
                "the license-gated Alcove API must never be a sweepable recipe")
            #expect(recipe.install?.requestHeaders.isEmpty != false,
                "an Alcove recipe must not carry injected request headers")
        }
        #expect(!GitHubReleaseRegistry.rules.contains { $0.bundleID == alcove })
    }

    /// CleanShot reaches its licensed feed through `ChannelBinding`, never a
    /// probe recipe. If one ever appears, the sweep would fetch a URL with the
    /// activation key in it.
    @Test func cleanShotHasNoProbeRecipe() {
        #expect(!VendorProbeRegistry.recipes.contains {
            $0.bundleID == CleanShotChannel.bundleID
        })
    }

    /// No recipe in the swept registries may carry a request header that isn't
    /// on the known-not-a-secret list — an injected header is the shape a
    /// credential takes, and the sweep can't tell by looking.
    @Test func noSweptRecipeCarriesAnUnknownInjectedHeader() {
        let reviewed: Set<String> = RegistrySecurity.nonSecretInjectedHeaders
            .union(["referer", "user-agent"])
        for recipe in VendorProbeRegistry.recipes {
            let headers = recipe.install?.requestHeaders ?? [:]
            for name in headers.keys {
                #expect(
                    reviewed.contains(name.lowercased()),
                    "\(recipe.bundleID) injects unreviewed header '\(name)'; confirm it is not a credential, then allow-list it")
            }
        }
    }

    /// A recipe may read out of a file that also holds credentials only at a
    /// path somebody has looked at. `ProbeIdentity`'s types cannot express that
    /// rule — `.jsonKey` reaches any top-level key, and `~/.codex/auth.json`
    /// keeps `OPENAI_API_KEY` at its top level — so the registry is checked
    /// against the allow-list directly.
    @Test func noRecipeReadsAnUnreviewedPathOutOfACredentialFile() {
        for recipe in VendorProbeRegistry.recipes {
            for identity in recipe.localReads {
                guard let allowed =
                    RegistrySecurity.credentialBearingFileReads[identity.displayPath]
                else { continue }
                #expect(
                    allowed.contains(identity.readPath),
                    "\(recipe.bundleID) reads '\(identity.readPath)' out of \(identity.displayPath); confirm it is not a credential, then allow-list it")
            }
        }
    }

    /// And the allow-list must describe the registry rather than outlive it. An
    /// entry no recipe performs is a standing permission for a read nobody
    /// makes, which the next reader would take as "this was decided to be fine".
    @Test func everyAllowedCredentialFileReadIsActuallyPerformed() {
        let performed = Set(
            VendorProbeRegistry.recipes
                .flatMap(\.localReads)
                .map { "\($0.displayPath)|\($0.readPath)" })
        for (file, reads) in RegistrySecurity.credentialBearingFileReads {
            for read in reads {
                #expect(
                    performed.contains("\(file)|\(read)"),
                    "the allow-list permits '\(read)' out of \(file), but no recipe reads it; drop the entry")
            }
        }
    }
}

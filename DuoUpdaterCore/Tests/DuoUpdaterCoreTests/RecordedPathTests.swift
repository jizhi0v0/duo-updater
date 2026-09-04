import Testing
import Foundation
@testable import DuoUpdaterCore

/// What survives of a URL's path on its way to disk.
///
/// Every fixture here is a real path from a real store, because the question
/// this type exists to answer is a trade and not a rule: it can only catch a
/// credential in a path segment by guessing which segments are credentials, and
/// every wrong guess destroys a diagnostic permanently. The cases are therefore
/// paired — one thing that must go, one neighbouring thing that must stay.
struct RecordedPathTests {

    // MARK: - What goes

    /// Mutation: dropping the label/opaque rule, keeping only the token shapes.
    ///
    /// The one path-borne opaque value in 590 real ones, recorded twice with two
    /// different UUIDs as the second hop of a redirect chain out of
    /// `artifacts.teamcity.jetbrains.com`. Whether that UUID is a live
    /// credential could not be proven — the recorded ones have expired and the
    /// entry URL no longer issues a presigned redirect — so this is written as
    /// "an opaque per-request value in a segment named for authentication",
    /// which is what it demonstrably is, and reason enough not to keep it.
    @Test("An opaque value in a segment labelled for auth does not reach disk")
    func aLabelledOpaqueSegmentIsRedacted() {
        let path = "/presignedTokenAuth/db8ca02c-d111-4d66-b1b6-3250958159d3"
            + "/guestAuth/repository/download/AndroidStudioReleasesList"
            + "/.lastSuccessful/android-studio-releases-list.json"

        let out = RecordedPath.redacted(path: path)

        #expect(!out.contains("db8ca02c-d111-4d66-b1b6-3250958159d3"))
        #expect(out.contains("/presignedTokenAuth/\(Redactor.placeholder)/"))
        // The rest of the path is what makes the row worth keeping at all.
        #expect(out.hasSuffix("/android-studio-releases-list.json"))
        #expect(out.contains("/guestAuth/repository/download/"))
    }

    /// Mutation: matching the label the way `CredentialBearingURL` matches a
    /// query parameter — folded name, or a separator-delimited tail.
    ///
    /// `presignedTokenAuth` has no separators, so that matching cannot see it
    /// and this is the case that forces the split on case as well.
    @Test("A label is recognised inside a camel-cased segment, not only a delimited one")
    func aCamelCasedLabelIsRecognised() {
        let uuid = "db8ca02c-d111-4d66-b1b6-3250958159d3"
        #expect(RecordedPath.redacted(path: "/presignedTokenAuth/\(uuid)/x")
            == "/presignedTokenAuth/\(Redactor.placeholder)/x")
        #expect(RecordedPath.redacted(path: "/x_auth_token/\(uuid)/x")
            == "/x_auth_token/\(Redactor.placeholder)/x")
    }

    /// Mutation: emptying `tokenShapes`.
    @Test("A known token shape goes wherever it sits, labelled or not")
    func aKnownTokenShapeIsRedactedAnywhere() {
        let out = RecordedPath.redacted(
            path: "/downloads/ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123/tool.zip")
        #expect(out == "/downloads/\(Redactor.placeholder)/tool.zip")
    }

    // MARK: - What stays

    /// Mutation: adding `\b[A-Fa-f0-9]{32,}\b` to `tokenShapes` — i.e. doing what
    /// sending the path through `Redactor` would have done.
    ///
    /// This is the case the whole type exists for. All four are real, and all
    /// four are build hashes: rewriting them buys nothing and costs the answer to
    /// "which build did it actually fetch".
    @Test("A build hash in an unlabelled segment is kept")
    func buildHashesSurvive() {
        for path in [
            "/dbazure/download/stable/a44adf7f53e00964ab890f9f8758a334f1fc15bc/VSCode-darwin-arm64.zip",
            "/production/90de2327392570a5f5f625c656c6749d228e6437/darwin/arm64/Cursor-darwin-arm64.dmg",
            "/releases/darwin/universal/1.46388.1/Claude-2dfd5f2c40e82ccf388f5dc1d3f1ce93a3671b03.zip",
            "/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608060_darwin_arm64.pkg",
        ] {
            #expect(RecordedPath.redacted(path: path) == path)
        }
    }

    /// Mutation: `isOpaque` returning true unconditionally — dropping the test
    /// that actually carries the safety.
    ///
    /// `/license/issue-token` is real, and `issue-token` is an endpoint name. A
    /// label alone is not evidence of a secret behind it.
    @Test("A labelled segment followed by a readable value keeps the value")
    func aLabelWithoutAnOpaqueValueChangesNothing() {
        #expect(RecordedPath.redacted(path: "/license/issue-token") == "/license/issue-token")
        // `1Password` is a label under the case-splitting rule — the version
        // after it is what saves the path, which is why the opacity test and not
        // the label list is where the safety lives.
        #expect(RecordedPath.redacted(path: "/1Password/8.10.44/1Password-8.10.44.zip")
            == "/1Password/8.10.44/1Password-8.10.44.zip")
        #expect(RecordedPath.redacted(path: "/mac/1Password-latest-aarch64.zip")
            == "/mac/1Password-latest-aarch64.zip")
    }

    /// Mutation: looking at the *following* segment for a label as well as the
    /// preceding one.
    ///
    /// Paths end in filenames, and a filename is allowed to say "auth" without
    /// condemning the hash in front of it.
    @Test("A label in the filename does not condemn the segment before it")
    func aTrailingLabelDoesNotReachBackwards() {
        // The filename has to contain a word the label list actually holds, or
        // this case cannot tell the two implementations apart — the first
        // version used `oauth-config.json`, whose words are `oauth`/`config`/
        // `json` and none of which is in the list, so the forward-looking
        // mutation passed it. `auth-config.json` splits to `auth`, which is.
        let path = "/build/9f8e7d6c5b4a3928170695e4/auth-config.json"
        #expect(RecordedPath.redacted(path: path) == path)
    }

    /// Mutation: joining on something other than "/", or dropping empty fields.
    ///
    /// The path is rebuilt from its parts, so the separators have to come back
    /// exactly — a lost leading slash turns an absolute path into a relative one
    /// in every row, silently.
    @Test("Paths that need no change come back byte for byte")
    func untouchedPathsAreRebuiltExactly() {
        for path in ["/", "", "/feed.xml", "/a//b/", "/pub/firefox/releases/155.0/mac/en-US/Firefox 155.0.dmg"] {
            #expect(RecordedPath.redacted(path: path) == path)
        }
    }
}

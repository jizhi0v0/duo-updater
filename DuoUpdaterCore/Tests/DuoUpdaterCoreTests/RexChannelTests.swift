import Foundation
import Testing
@testable import DuoUpdaterCore

struct RexChannelTests {
    @Test func explicitPreferenceOverridesEitherShippedFeed() {
        for feed in [RexChannel.previewFeed, RexChannel.snapshotFeed] {
            #expect(RexChannel.resolve(preference: "preview", declaredFeed: feed)
                == ResolvedChannel(channel: .preview, feedOverride: RexChannel.previewFeed))
            #expect(RexChannel.resolve(preference: "snapshot", declaredFeed: feed)
                == ResolvedChannel(channel: .nightly, feedOverride: RexChannel.snapshotFeed))
        }
    }

    @Test func missingOrUnknownPreferenceKeepsTheShippedFeed() {
        for preference in [nil, "unknown"] as [String?] {
            #expect(RexChannel.resolve(preference: preference, declaredFeed: RexChannel.previewFeed)?.channel == .preview)
            #expect(RexChannel.resolve(preference: preference, declaredFeed: RexChannel.snapshotFeed)?.channel == .nightly)
        }
    }

    @Test func unrecognizedFeedIsNotOverridden() {
        let otherFeed = URL(string: "https://blob.superlogical.com/public/rex-app/stable-arm64/appcast.xml")!
        #expect(RexChannel.resolve(preference: "snapshot", declaredFeed: otherFeed) == nil)
    }

    @Test func toggleChangesFingerprintWithoutBundleMetadata() {
        #expect(RexChannel.resolve(preference: nil) == nil)
        #expect(RexChannel.resolve(preference: "preview") != RexChannel.resolve(preference: "snapshot"))
    }
}

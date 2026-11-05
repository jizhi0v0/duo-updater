import Testing

struct BuildReleaseChannelTests {
    @Test func stableAndUnknownBuildsRefuseEvenPersistedOptIn() {
        for info: [String: Any] in [[:], ["DuoReleaseChannel": "stable"],
                                    ["DuoReleaseChannel": "nightly"],
                                    ["DuoUpdaterBetaChannel": true]] {
            #expect(!BuildReleaseChannel.permitsAutomaticUpdates(info: info, enabled: true))
        }
    }

    @Test func betaBuildStillRequiresExplicitAutomaticUpdateConsent() {
        let info: [String: Any] = ["DuoReleaseChannel": "beta"]
        #expect(BuildReleaseChannel.permitsAutomaticUpdates(info: info, enabled: true))
        #expect(!BuildReleaseChannel.permitsAutomaticUpdates(info: info, enabled: false))
    }
}

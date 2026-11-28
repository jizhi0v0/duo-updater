import Testing

@testable import DuoUpdaterCore

@Suite struct KodiChannelRoutingTests {
    @Test(arguments: [
        ("21.3.", ReleaseChannel.stable),
        ("22.0", .stable),
        ("22.0.rc2", .rc),
        ("22.0.beta2", .beta),
        ("23.0.alpha1", .alpha),
    ])
    func detectsKodiStages(_ example: (version: String, channel: ReleaseChannel)) {
        #expect(ReleaseChannel.detect(
            name: "Kodi", bundleID: "org.xbmc.kodi", keystoneChannel: nil,
            version: example.version) == example.channel)
    }

    @Test func unrelatedBundleDoesNotInheritKodiStages() {
        #expect(ReleaseChannel.detect(
            name: "Example", bundleID: "org.example.player", keystoneChannel: nil,
            version: "22.0.rc2") == .stable)
    }
}

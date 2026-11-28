import Testing

@testable import DuoUpdaterCore

@Suite struct TaskPaperChannelRoutingTests {
    @Test func directPreviewUsesTheSignedBundlesVersionSuffix() {
        let bundleID = "com.hogbaysoftware.TaskPaper3.direct"
        #expect(ReleaseChannel.detect(
            name: "TaskPaper", bundleID: bundleID, keystoneChannel: nil,
            version: "3.9.4 Preview") == .preview)
        #expect(ReleaseChannel.detect(
            name: "TaskPaper", bundleID: bundleID, keystoneChannel: nil,
            version: "3.9.4") == .stable)
        #expect(ReleaseChannel.detect(
            name: "Example", bundleID: "org.example.editor", keystoneChannel: nil,
            version: "3.9.4 Preview") == .stable)
    }
}

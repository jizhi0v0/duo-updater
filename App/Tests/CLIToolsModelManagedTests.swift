import Foundation
import Testing
import DuoUpdaterCore

/// `CLIToolsModel` with managed rows (`CLITools/Managed/`): a row whose
/// directory moves between checks is one row, its lane and its GitHub pause
/// are its manager's, and a pinned request is never an offer. Scripted
/// providers as in `CLIToolsModelTests`; nothing reaches the host.
///
/// Each case names the mutation it fails under.
@MainActor
struct CLIToolsModelManagedTests {

    typealias T = CLIToolsModelTests

    static let root = "/Users/u/.local/share/zz"

    /// A managed row named by `key` under `root`, sitting in `installPath` now.
    static func managed(
        key: String = "node@20", installPath: String = root + "/installs/node/20.10.0",
        installed: String? = "20.10.0", latest: String? = "20.20.2", state: CLIToolState = .updateAvailable,
        oneClick: Bool = true, request: ManagedItem.Request? = ManagedItem.Request(kind: .range, spelled: "20"),
        descriptor: ManagerDescriptor = T.fakeManager, effects: [ManagedItem.Effect] = []
    ) -> CLIToolStatus {
        let item = ManagedItem(
            descriptor: descriptor, root: root, key: key, name: String(key.prefix { $0 != "@" }),
            installPath: installPath, shape: .request, request: request, installed: installed,
            latestWithinRequest: latest, effects: effects)
        let command = CLIToolCommand(executable: "/Users/u/.local/bin/zz", arguments: ["upgrade", "-y", item.name], pathPrefix: nil)
        return CLIToolStatus(
            kind: .managed, path: installPath, identity: item.identity, installedVersion: installed,
            latestVersion: latest, channel: nil, state: state, oneClick: oneClick ? command : nil,
            withheld: nil, note: nil, manualCommand: state == .pinned ? command : nil, name: item.name,
            detail: .managed(item))
    }

    static func id(_ status: CLIToolStatus) -> CLIToolID { CLIToolID(kind: .managed, path: status.identity) }

    static func model(_ reports: [CLIToolReport], updater: T.FakeUpdater = T.FakeUpdater()) -> CLIToolsModel {
        let provider = T.FakeProvider(kind: .managed, checker: T.FakeCheck(reports.map { ($0, nil) }), updater: updater,
                                      providerID: T.fakeManager.providerID)
        return T.model([provider])
    }

    /// The row keeps its identity while its directory moves: the update's
    /// "Updated to X" lands on the re-checked row, whose path is the new
    /// patch's. Mutation: build `CLIToolID` from `path` instead of `identity`
    /// (the click finds no offer; the re-check brings a second row).
    @Test func aRowKeepsItsIdentityWhileItsDirectoryMoves() async {
        let before = Self.managed()
        let after = Self.managed(installPath: Self.root + "/installs/node/20.20.2", installed: "20.20.2",
                                 state: .upToDate, oneClick: false)
        #expect(before.identity == after.identity)
        #expect(before.path != after.path)
        let updater = T.FakeUpdater()
        await updater.set(Self.id(before), .updated(version: "20.20.2"))
        let model = Self.model([T.report(.managed, [before]), T.report(.managed, [after])], updater: updater)
        await model.refresh()
        #expect(model.offered.map(\.identity) == [before.identity])

        await model.update(Self.id(before))

        #expect(model.justUpdated[Self.id(before)] == "20.20.2")
        #expect(model.statuses.map(\.path) == [after.path])
        #expect(model.statuses.map(\.toolID) == [Self.id(before)])
        #expect(model.outdated.isEmpty)
        #expect(await updater.calls == [Self.id(before)])
    }

    /// A managed row's lane is its manager's (`ManagerDescriptor.lane`): uv
    /// tools share uv's with uv itself. Mutation: drop the `.managed` arm of
    /// `lane(of:)` (the row gets "managed", a lane of its own).
    @Test func theLaneIsTheManagers() {
        #expect(CLIToolsModel.lane(of: Self.managed()) == "uv")
        #expect(CLIToolsModel.lane(of: Self.managed()) == CLIToolsModel.lane(of: T.status("/Users/u/.local/bin/uv", kind: .uv)))
        let own = ManagerDescriptor(id: ManagerID("zz-own"), displayName: "ZZ own", signer: nil, logo: nil, tint: .label, lane: "zz-own")
        #expect(CLIToolsModel.lane(of: Self.managed(descriptor: own)) == "zz-own")
    }

    /// The GitHub pause holds a managed one-click back by its manager's rule:
    /// a manager whose upgrade spends our token (mise's rule) while the
    /// token's budget is closed; one with no rule never. Mutation: read
    /// `CLIToolKind.updaterSpendsGitHubAPI` (nil for `.managed`).
    @Test func thePauseReadsTheManagersRule() async {
        let spends = Self.managed()
        let quiet = Self.managed(key: "jq@1", descriptor: ManagerDescriptor(
            id: ManagerID("zz-quiet"), displayName: "ZZ quiet", signer: nil, logo: nil, tint: .label, lane: "zz-quiet"))
        let model = Self.model([T.report(.managed, [spends, quiet])])
        model.updatersGetOurToken = true
        model.gitHubPause = [.token: Date().addingTimeInterval(600)]
        await model.refresh()
        #expect(model.offered.map(\.identity) == [quiet.identity])
        #expect(model.heldBack.map(\.identity) == [spends.identity])
        #expect(model.status(Self.id(spends))?.withheld == .rateLimited)
        model.gitHubPause = [:]
        #expect(Set(model.offered.map(\.identity)) == [spends.identity, quiet.identity])
    }

    /// A pinned request is reported, never offered or counted — in the
    /// managed groups as in npm's. Mutation: count `.pinned` in `outdated`.
    @Test func aPinnedRequestIsNeverOffered() async {
        let pinned = Self.managed(key: "jq@1.6", installed: "1.6", latest: "1.8.1", state: .pinned, oneClick: false,
                                  request: ManagedItem.Request(kind: .exact, spelled: "1.6"))
        let model = Self.model([T.report(.managed, [pinned, Self.managed()])])
        await model.refresh()
        #expect(model.statuses.count == 2)
        #expect(model.offered.map(\.identity) == [Self.managed().identity])
        #expect(model.outdated.count == 1)
        #expect(!model.batchOffered.contains { $0.identity == pinned.identity })
        #expect(model.status(Self.id(pinned))?.commandToCopy != nil)
    }

    /// Two managers' providers are both `.managed`; each row's update goes to
    /// its own manager's provider, found by id, and each re-check asks that
    /// provider only. Mutation: look the provider up by kind (the first
    /// managed provider answers for both).
    @Test func eachRowUpdatesThroughItsOwnManagersProvider() async {
        let other = ManagerDescriptor(id: ManagerID("zz-other"), displayName: "ZZ other", signer: nil, logo: nil, tint: .label, lane: "zz-other")
        let mine = Self.managed()
        let theirs = Self.managed(key: "ruff", descriptor: other)
        let mineUpdater = T.FakeUpdater()
        let theirsUpdater = T.FakeUpdater()
        await theirsUpdater.set(Self.id(theirs), .updated(version: "0.9.0"))
        let a = T.FakeProvider(kind: .managed, checker: T.FakeCheck([(T.report(.managed, [mine]), nil)]), updater: mineUpdater,
                               providerID: T.fakeManager.providerID)
        let b = T.FakeProvider(kind: .managed, checker: T.FakeCheck([(T.report(.managed, [theirs]), nil)]), updater: theirsUpdater,
                               providerID: other.providerID)
        let model = T.model([a, b])
        await model.refresh()
        #expect(model.statuses.map(\.identity) == [mine.identity, theirs.identity])

        await model.update(Self.id(theirs))

        #expect(await theirsUpdater.calls == [Self.id(theirs)])
        #expect(await mineUpdater.calls.isEmpty)
        #expect(model.justUpdated[Self.id(theirs)] == "0.9.0")
    }
}

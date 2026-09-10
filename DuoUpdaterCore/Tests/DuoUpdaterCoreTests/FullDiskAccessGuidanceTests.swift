import Testing
@testable import DuoUpdaterCore

@Suite("FullDiskAccessGuidance")
struct FullDiskAccessGuidanceTests {
    typealias G = FullDiskAccessGuidance

    /// Mutation: answer `false` for a fresh state — nobody is ever told why their
    /// TestFlight rows show a question mark.
    @Test func asksOnceWhenAnAppNeedsItAndItIsMissing() {
        #expect(G.shouldAsk(fullDiskAccess: .denied, needing: ["a"], state: .init()))
        #expect(G.shouldAsk(fullDiskAccess: .notDetermined, needing: ["a"], state: .init()))
    }

    /// Mutation: drop the `.granted` / `.unknown` case — a Mac that already has it,
    /// or one where the status cannot be read, is asked anyway.
    @Test func neverAsksWhenGrantedOrUnknowable() {
        #expect(!G.shouldAsk(fullDiskAccess: .granted, needing: ["a"], state: .init()))
        #expect(!G.shouldAsk(fullDiskAccess: .unknown, needing: ["a"], state: .init()))
    }

    /// Mutation: drop `!needing.isEmpty` — every Mac without it is asked, whether
    /// or not anything on it would be checked any better.
    @Test func neverAsksWithoutAnAppThatNeedsIt() {
        #expect(!G.shouldAsk(fullDiskAccess: .denied, needing: [], state: .init()))
    }

    /// The second ask is for a NEW need only. Mutation: drop the subset check —
    /// the same apps are asked about a second time; answer `false` for any second
    /// ask — a first "Not Now" by mistake is final.
    @Test func asksASecondTimeOnlyForANewApp() {
        let once = G.State(timesAsked: 1, appsWhenLastAsked: ["a"])
        #expect(!G.shouldAsk(fullDiskAccess: .denied, needing: ["a"], state: once))
        #expect(G.shouldAsk(fullDiskAccess: .denied, needing: ["a", "b"], state: once))
        #expect(G.shouldAsk(fullDiskAccess: .denied, needing: ["b"], state: once))
    }

    /// Mutation: compare with `<=` — a third ask happens.
    @Test func neverAsksAThirdTime() {
        let twice = G.State(timesAsked: 2, appsWhenLastAsked: ["a"])
        #expect(!G.shouldAsk(fullDiskAccess: .denied, needing: ["a", "b"], state: twice))
    }

    /// Mutation: keep the old count, or the old apps — the cap never arrives, or
    /// the second ask repeats the first.
    @Test func recordingCountsTheAskAndRemembersItsApps() {
        let after = G.recordingAsk(G.State(timesAsked: 1, appsWhenLastAsked: ["a"]), needing: ["a", "b"])
        #expect(after == G.State(timesAsked: 2, appsWhenLastAsked: ["a", "b"]))
    }

    /// Once Grant… has been pressed this run and it is still missing, the tips
    /// offer a relaunch: the running process does not see the switch until it
    /// restarts. Mutations: drop the `grantRequestedThisRun` term — every tip
    /// offers a relaunch before anyone pressed Grant…; answer true for `.granted`
    /// or `.unknown` — a Mac that has it, or cannot tell, is told to relaunch.
    @Test func offersARelaunchOnlyAfterGrantWasPressed() {
        #expect(!G.offersRelaunch(fullDiskAccess: .denied, grantRequestedThisRun: false))
        #expect(G.offersRelaunch(fullDiskAccess: .denied, grantRequestedThisRun: true))
        #expect(G.offersRelaunch(fullDiskAccess: .notDetermined, grantRequestedThisRun: true))
        #expect(!G.offersRelaunch(fullDiskAccess: .granted, grantRequestedThisRun: true))
        #expect(!G.offersRelaunch(fullDiskAccess: .unknown, grantRequestedThisRun: true))
    }
}

@Suite("FullDiskAccessNeeds")
struct FullDiskAccessNeedsTests {

    /// Mutation: answer `true` for a prerelease — a CotEditor beta, whose version
    /// already settles its channel, carries a mark for nothing; answer `false` for
    /// stable — the one copy the missing read can mislead is never marked.
    @Test func cotEditorIsMarkedOnlyOnAStableCopy() {
        #expect(FullDiskAccessNeed.cotEditorChannel.mayAffect(releaseChannel: .stable))
        #expect(!FullDiskAccessNeed.cotEditorChannel.mayAffect(releaseChannel: .beta))
    }

    /// Mutation: answer `true` — a TestFlight row would carry this mark next to its
    /// own question mark, saying the same thing twice.
    @Test func aTestFlightRowIsNeverMarkedTwice() {
        for channel in ReleaseChannel.allCases {
            #expect(!FullDiskAccessNeed.testFlight.mayAffect(releaseChannel: channel))
        }
    }

    /// Mutation: drop the `recordRefusal` call in `mayRead` — the read is still
    /// skipped, but the menu never learns which app it cost.
    @Test func aRefusedReadIsSkippedAndRemembersItsApps() {
        let needs = FullDiskAccessNeeds()
        #expect(!needs.mayRead(.cotEditorChannel, for: ["zz.fixture.editor"], fullDiskAccess: .denied))
        #expect(needs.refused() == [.cotEditorChannel: ["zz.fixture.editor"]])
    }

    /// Mutation: record whatever the answer — a Mac that has the grant, or where it
    /// cannot be asked about, is told about apps that were read just fine.
    @Test func anAdmittedReadRemembersNothing() {
        let needs = FullDiskAccessNeeds()
        #expect(needs.mayRead(.testFlight, for: ["zz.fixture.beta"], fullDiskAccess: .granted))
        #expect(needs.mayRead(.testFlight, for: ["zz.fixture.beta"], fullDiskAccess: .unknown))
        #expect(needs.refused().isEmpty)
    }

    /// Refusals add up across reads and kinds of read. Mutation: assign instead of
    /// union — each read would erase the apps the one before it recorded.
    @Test func refusalsAccumulate() {
        let needs = FullDiskAccessNeeds()
        needs.recordRefusal(.testFlight, for: ["zz.fixture.a"])
        needs.recordRefusal(.testFlight, for: ["zz.fixture.b"])
        needs.recordRefusal(.cotEditorChannel, for: ["zz.fixture.editor"])
        #expect(needs.refused() == [
            .testFlight: ["zz.fixture.a", "zz.fixture.b"],
            .cotEditorChannel: ["zz.fixture.editor"],
        ])
    }

    /// A round with no TestFlight betas records nothing. Mutation: drop the
    /// empty guard — an empty entry would make `refused()` non-empty for a Mac
    /// that has nothing to explain.
    @Test func noAppsRecordNothing() {
        let needs = FullDiskAccessNeeds()
        needs.recordRefusal(.testFlight, for: [])
        #expect(needs.refused().isEmpty)
    }
}

import Testing
import Foundation
import os
@testable import DuoUpdaterCore

/// `BrewAskPass`: the program brew's sudo runs for the password, driven here
/// the way sudo drives it — exec'd as a child, its standard output read as the
/// password, empty output taken as none (sudo(8) `-A`). No sudo runs: the
/// script is the whole contract between the two. `/usr/bin/time` stands in
/// for sudo — a program that runs the askpass as its child and waits, as sudo
/// does — and is the only ancestor `isSudo` takes for sudo here. The last test
/// runs it from an invented `brew` through `BrewFormulaService` (CLAUDE.md
/// "测试不能问宿主").
@Suite struct BrewAskPassTests {

    /// What the prompt was asked, in order.
    private final class Asked: Sendable {
        let requests = OSAllocatedUnfairLock<[SudoPasswordRequest]>(initialState: [])
        var all: [SudoPasswordRequest] { requests.withLock { $0 } }
        func record(_ request: SudoPasswordRequest) { requests.withLock { $0.append(request) } }
    }

    /// The stand-in sudo, and the tests' `isSudo`.
    private static let sudo = "/usr/bin/time"
    private static let isSudo: BrewAskPass.IsSudo = { $0 == sudo }

    /// A parent directory of the test's own, with a quote in its name: the
    /// script names its directory inside single quotes. Short: the socket's
    /// path has to fit `sun_path`.
    private static func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BAP it's-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The program run as sudo runs it, under a "sudo" of its own: a
    /// different one each call, as two sudo calls in one brew run are.
    private static func askpass(_ environment: [String: String]) async throws -> ChildProcess.Outcome {
        let program = try #require(environment["SUDO_ASKPASS"])
        return try await ChildProcess.run(sudo, [program, "Password:"], onCancel: .terminateChild)
    }

    /// The program run twice by one "sudo", as a sudo asks again after a
    /// wrong password.
    private static func askpassTwiceFromOneSudo(_ environment: [String: String]) async throws -> ChildProcess.Outcome {
        let program = try #require(environment["SUDO_ASKPASS"])
        return try await ChildProcess.run(
            sudo, ["/bin/sh", "-c", "\"$0\" Password:; \"$0\" Password:", program], onCancel: .terminateChild)
    }

    private static func output(_ outcome: ChildProcess.Outcome) -> String {
        String(decoding: outcome.standardOutput, as: UTF8.self)
    }

    /// Mutation: write the answer without its newline, or quote the directory
    /// unsafely → the script hangs or prints something else. Mutation: leave the
    /// directory behind → the last expectation fails.
    @Test func theProgramPrintsWhatThePromptAnswers() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        let password = #"pa ss'w\d"$x"#
        var directory: URL?
        try await BrewAskPass.withChannel(
            packages: ["zulu@25"],
            prompt: { asked.record($0); return password },
            temporaryDirectory: parent,
            isSudo: Self.isSudo
        ) { environment in
            let program = URL(fileURLWithPath: try #require(environment["SUDO_ASKPASS"]))
            directory = program.deletingLastPathComponent()
            let mode = try FileManager.default.attributesOfItem(atPath: program.deletingLastPathComponent().path)[.posixPermissions] as? Int
            #expect(mode == 0o700)
            let outcome = try await Self.askpass(environment)
            #expect(outcome.terminationStatus == 0)
            #expect(Self.output(outcome) == password + "\n")
        }
        #expect(asked.all == [SudoPasswordRequest(packages: ["zulu@25"], attempt: 1)])
        #expect(!FileManager.default.fileExists(atPath: try #require(directory).path))
    }

    /// The same sudo asking again follows a wrong password: attempt 2. Another
    /// sudo of the run asking is attempt 1 — its credential cache may simply
    /// have run out. Mutation: count asks per run → the panel says "didn't
    /// work" to a later sudo whose password was right.
    @Test func attemptsCountPerSudo() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        try await BrewAskPass.withChannel(
            packages: ["a"], prompt: { asked.record($0); return "pw" }, temporaryDirectory: parent,
            isSudo: Self.isSudo
        ) { environment in
            #expect(Self.output(try await Self.askpassTwiceFromOneSudo(environment)) == "pw\npw\n")
            _ = try await Self.askpass(environment)
            _ = try await Self.askpass(environment)
        }
        #expect(asked.all.map(\.attempt) == [1, 2, 1, 1])
    }

    /// Declining answers no password (sudo gives up on an empty read), and the
    /// run does not ask again. Mutation: drop `declined` → a second panel.
    @Test func aDeclineFailsTheAskAndIsNotAskedAgain() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        try await BrewAskPass.withChannel(
            packages: ["zulu@25"], prompt: { asked.record($0); return nil }, temporaryDirectory: parent,
            isSudo: Self.isSudo
        ) { environment in
            for _ in 0..<2 {
                let outcome = try await Self.askpass(environment)
                #expect(outcome.terminationStatus == 1)
                #expect(outcome.standardOutput.isEmpty)
            }
        }
        #expect(asked.all.count == 1)
    }

    /// What the script can't hand on whole is no password: empty, or with a
    /// CR, LF or NUL in it. `"pw\r\n".contains("\n")` is false in Swift (one
    /// Character), so the check is on bytes. Mutation: check Characters → the
    /// CRLF answer reaches sudo and its trailing LF answers the next ask.
    @Test func anAnswerThatIsNotOneLineIsNoPassword() async throws {
        for bad in ["", "pw\r\n", "pw\r", "p\nw", "p\u{0}w"] {
            let parent = try Self.parent()
            defer { try? FileManager.default.removeItem(at: parent) }
            try await BrewAskPass.withChannel(
                packages: ["x"], prompt: { _ in bad }, temporaryDirectory: parent, isSudo: Self.isSudo
            ) { environment in
                let outcome = try await Self.askpass(environment)
                #expect(outcome.standardOutput.isEmpty, "answer \(bad.debugDescription)")
            }
        }
    }

    /// An ask from a process with no sudo between it and this one — the
    /// program run straight from here, or a bare connection to the socket — is
    /// neither asked nor answered; the run's own sudo still is, after. Mutation:
    /// drop the sudo requirement (any ancestry that reaches this process will
    /// do) → both get the password and the prompt is asked three times.
    @Test func anAskWithNoSudoOnTheWayIsNeitherAskedNorAnswered() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        try await BrewAskPass.withChannel(
            packages: ["x"], prompt: { asked.record($0); return "pw" }, temporaryDirectory: parent,
            isSudo: Self.isSudo
        ) { environment in
            let program = try #require(environment["SUDO_ASKPASS"])
            let direct = try await ChildProcess.run(program, ["Password:"], onCancel: .terminateChild)
            #expect(direct.standardOutput.isEmpty)
            #expect(direct.terminationStatus == 1)
            let socket = URL(fileURLWithPath: program).deletingLastPathComponent().appendingPathComponent("s").path
            let bare = try await ChildProcess.run(
                "/bin/sh", ["-c", #"printf 'ask 1 2\n' | /usr/bin/nc -U "$0""#, socket], onCancel: .terminateChild)
            #expect(bare.standardOutput.isEmpty)
            #expect(asked.all.isEmpty)
            #expect(Self.output(try await Self.askpass(environment)) == "pw\n")
        }
        #expect(asked.all == [SudoPasswordRequest(packages: ["x"], attempt: 1)])
    }

    /// An ask under a sudo that isn't this process's descendant — an orphan
    /// whose parent is launchd now, as a double fork leaves it — is neither
    /// asked nor answered. The orphan waits until it is one before it asks.
    /// Mutation: take the sudo found so far when the walk reaches launchd →
    /// the orphan gets the password.
    @Test func anAskFromOutsideThisProcessIsNeitherAskedNorAnswered() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        let out = parent.appendingPathComponent("out")
        let done = parent.appendingPathComponent("done")
        try await BrewAskPass.withChannel(
            packages: ["x"], prompt: { asked.record($0); return "pw" }, temporaryDirectory: parent,
            isSudo: Self.isSudo
        ) { environment in
            let program = try #require(environment["SUDO_ASKPASS"])
            let orphan = #"""
            until [ "$(ps -o ppid= -p "$PPID" | tr -d ' ')" = 1 ]; do sleep 0.05; done
            "$0" Password: > "$1"; : > "$2"
            """#
            _ = try await ChildProcess.run(
                "/bin/sh", ["-c", #"( "$0" /bin/sh -c "$1" "$2" "$3" "$4" >/dev/null 2>&1 & ); :"#,
                            Self.sudo, orphan, program, out.path, done.path],
                onCancel: .terminateChild)
            while !FileManager.default.fileExists(atPath: done.path) { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(try Data(contentsOf: out).isEmpty)
        #expect(asked.all.isEmpty)
    }

    /// The run ending while the panel is up cancels the prompt (the app's panel
    /// closes on cancel): no panel for a run that is over, no password for its
    /// sudo. Asserted on the cancel itself, not on time (REVIEW.md: no
    /// wall-clock bounds in the core suite). Mutation: don't cancel in `close`
    /// → the prompt sleeps out its 30 s uncancelled and `cancelled` is false
    /// (the script still gets nothing: `closing` drops the late answer).
    @Test func closingCancelsAPromptStillUp() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        var script: Task<ChildProcess.Outcome, any Error>?
        try await BrewAskPass.withChannel(
            packages: ["x"],
            prompt: { request in
                asked.record(request)
                try? await Task.sleep(for: .seconds(30))
                cancelled.withLock { $0 = Task.isCancelled }
                return "late"
            },
            temporaryDirectory: parent,
            isSudo: Self.isSudo
        ) { environment in
            script = Task { try await Self.askpass(environment) }
            while asked.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(cancelled.withLock { $0 })
        let outcome = try await #require(script).value
        #expect(outcome.standardOutput.isEmpty)
    }

    /// No prompt: no `SUDO_ASKPASS`, and nothing made on disk.
    @Test func withoutAPromptBrewGetsNoAskpass() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let environment = try await BrewAskPass.withChannel(
            packages: ["x"], prompt: nil, temporaryDirectory: parent
        ) { $0 }
        #expect(environment.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    /// A program that can't be made doesn't fail the run: it goes on without
    /// one, as a cask that needs no sudo would. Mutation: rethrow → every cask
    /// upgrade fails when the temporary directory is unusable.
    @Test func aChannelThatCantBeMadeLeavesTheRunWithoutOne() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("BrewAskPassTests-missing-\(UUID().uuidString)")
        let environment = try await BrewAskPass.withChannel(
            packages: ["x"], prompt: { _ in "pw" }, temporaryDirectory: missing
        ) { $0 }
        #expect(environment.isEmpty)
    }

    /// A directory whose socket path wouldn't fit `sun_path` (104 bytes with
    /// its NUL) gives no program, as any other that can't be made, and leaves
    /// nothing behind. Mutation: drop the length check → the path is cut short,
    /// the socket bound where the program doesn't look, and a program handed
    /// out that is never answered.
    @Test func aSocketPathTooLongLeavesTheRunWithoutOne() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let deep = parent.appendingPathComponent(String(repeating: "d", count: 60))
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let environment = try await BrewAskPass.withChannel(
            packages: ["x"], prompt: { _ in "pw" }, temporaryDirectory: deep, isSudo: Self.isSudo
        ) { $0 }
        #expect(environment.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: deep.path).isEmpty)
    }

    /// A body that throws still removes the directory.
    @Test func aFailedRunStillCleansUp() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await BrewAskPass.withChannel(
                packages: ["x"], prompt: { _ in "pw" }, temporaryDirectory: parent
            ) { _ in throw Boom() }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    /// Through the service: only the cask upgrade gets `SUDO_ASKPASS`, the
    /// program it names answers with the prompt's password, and the panel
    /// names the cask that needs sudo. The invented `brew` logs each call with
    /// whether the variable was set, and runs it on `upgrade --cask` under the
    /// stand-in sudo, as brew's sudo would. Mutation: drop the askpass environment from
    /// `runCaskUpgrade` → `got` is empty and the call reads `|unset`.
    @Test func theCaskUpgradeAndOnlyItGetsTheProgram() async throws {
        let dir = try Self.parent()
        defer { try? FileManager.default.removeItem(at: dir) }
        let brew = dir.appendingPathComponent("brew")
        try Data(#"""
        #!/bin/sh
        d=$(dirname "$0")
        printf '%s|%s\n' "$*" "${SUDO_ASKPASS:+set}${SUDO_ASKPASS:-unset}" | sed 's/|set.*/|set/' >> "$d/calls"
        case "$*" in
          "upgrade --cask zzfixture-jdk zzfixture-cli") /usr/bin/time "$SUDO_ASKPASS" Password: > "$d/got" ;;
        esac
        exit 0
        """#.utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let service = BrewFormulaService(
            executor: { _ in nil },
            caskFacts: { token, _, _ in .init(installsAnApp: false, needsSudo: token == "zzfixture-jdk") },
            brewPath: { brew.path },
            askpassIsSudo: Self.isSudo)
        let asked = Asked()
        try await service.upgradeAll(
            casks: ["zzfixture-jdk", "zzfixture-cli"],
            password: { asked.record($0); return "s3cret" }) { _ in }
        let calls = try String(contentsOf: dir.appendingPathComponent("calls"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(calls.filter { $0.hasSuffix("|set") } == ["upgrade --cask zzfixture-jdk zzfixture-cli|set"])
        #expect(calls.contains("upgrade --formula|unset"))
        #expect(try String(contentsOf: dir.appendingPathComponent("got"), encoding: .utf8) == "s3cret\n")
        #expect(asked.all == [SudoPasswordRequest(packages: ["zzfixture-jdk"], attempt: 1)])
    }
}

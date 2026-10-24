import Testing
import Foundation
import os
@testable import DuoUpdaterCore

/// `BrewAskPass`: the program brew's sudo runs for the password, driven here
/// the way sudo drives it — exec'd as a child, its standard output read as the
/// password, empty output taken as none (sudo(8) `-A`). No sudo runs: the
/// script is the whole contract between the two. The last test runs it from an
/// invented `brew` through `BrewFormulaService` (CLAUDE.md "测试不能问宿主").
@Suite struct BrewAskPassTests {

    /// What the prompt was asked, in order.
    private final class Asked: Sendable {
        let requests = OSAllocatedUnfairLock<[SudoPasswordRequest]>(initialState: [])
        var all: [SudoPasswordRequest] { requests.withLock { $0 } }
        func record(_ request: SudoPasswordRequest) { requests.withLock { $0.append(request) } }
    }

    /// A parent directory of the test's own, with a quote in its name: the
    /// script names its directory inside single quotes.
    private static func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrewAskPassTests it's-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The program run as sudo runs it: a child of this process, so every run
    /// here shares one parent — one "sudo".
    private static func askpass(_ environment: [String: String]) async throws -> ChildProcess.Outcome {
        let program = try #require(environment["SUDO_ASKPASS"])
        return try await ChildProcess.run(program, ["Password:"], onCancel: .terminateChild)
    }

    /// The program run from a shell of its own: a different parent each time,
    /// as two sudo calls in one brew run are.
    private static func askpassFromAnotherSudo(_ environment: [String: String]) async throws -> ChildProcess.Outcome {
        let program = try #require(environment["SUDO_ASKPASS"])
        return try await ChildProcess.run("/bin/sh", ["-c", "\"$0\" Password:; :", program], onCancel: .terminateChild)
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
            temporaryDirectory: parent
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
            packages: ["a"], prompt: { asked.record($0); return "pw" }, temporaryDirectory: parent
        ) { environment in
            _ = try await Self.askpass(environment)
            _ = try await Self.askpass(environment)
            _ = try await Self.askpassFromAnotherSudo(environment)
            _ = try await Self.askpassFromAnotherSudo(environment)
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
            packages: ["zulu@25"], prompt: { asked.record($0); return nil }, temporaryDirectory: parent
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
                packages: ["x"], prompt: { _ in bad }, temporaryDirectory: parent
            ) { environment in
                let outcome = try await Self.askpass(environment)
                #expect(outcome.standardOutput.isEmpty, "answer \(bad.debugDescription)")
            }
        }
    }

    /// A reply meant for a script that died before reading it stays in the
    /// FIFO; the next script must skip it and wait for its own. Here the dead
    /// script's request is written straight to `request`. Mutation: read the
    /// first line whatever it says → the live script prints "FIRST".
    @Test func aStaleReplyIsNeverTakenForAnotherAsk() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let answers = OSAllocatedUnfairLock(initialState: ["FIRST", "SECOND"])
        let asked = Asked()
        try await BrewAskPass.withChannel(
            packages: ["x"],
            prompt: { request in asked.record(request); return answers.withLock { $0.removeFirst() } },
            temporaryDirectory: parent
        ) { environment in
            let directory = URL(fileURLWithPath: try #require(environment["SUDO_ASKPASS"])).deletingLastPathComponent()
            let fd = open(directory.appendingPathComponent("request").path, O_WRONLY | O_NONBLOCK)
            #expect(fd >= 0)
            let line = Array("ask 2147483000 1\n".utf8)
            _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
            while asked.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            let outcome = try await Self.askpass(environment)
            #expect(Self.output(outcome) == "SECOND\n")
        }
    }

    /// The run ending while the panel is up closes it (the prompt is
    /// cancelled) and returns at once: no panel for a run that is over, no
    /// password for its sudo. Mutation: don't cancel in `close` → this waits
    /// the prompt's 30 s and the script gets "late".
    @Test func closingCancelsAPromptStillUp() async throws {
        let parent = try Self.parent()
        defer { try? FileManager.default.removeItem(at: parent) }
        let asked = Asked()
        let started = ContinuousClock.now
        var script: Task<ChildProcess.Outcome, any Error>?
        try await BrewAskPass.withChannel(
            packages: ["x"],
            prompt: { request in
                asked.record(request)
                try? await Task.sleep(for: .seconds(30))
                return Task.isCancelled ? nil : "late"
            },
            temporaryDirectory: parent
        ) { environment in
            script = Task { try await Self.askpass(environment) }
            while asked.all.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(ContinuousClock.now - started < .seconds(10))
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
    /// whether the variable was set, and runs it on `upgrade --cask` as brew's
    /// sudo would. Mutation: drop the askpass environment from
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
          "upgrade --cask zzfixture-jdk zzfixture-cli") "$SUDO_ASKPASS" Password: > "$d/got" ;;
        esac
        exit 0
        """#.utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let service = BrewFormulaService(
            executor: { _ in nil },
            caskFacts: { token, _, _ in .init(installsAnApp: false, needsSudo: token == "zzfixture-jdk") },
            brewPath: { brew.path })
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

import Testing
import Foundation
@testable import DuoUpdaterCore

struct CLIToolProcessOriginTests {

    typealias Origin = CLIToolProcessOrigin
    let launchd = Origin.Ancestor(pid: 1, path: "/sbin/launchd", name: "launchd")

    func origin(_ executable: String, _ ancestors: [Origin.Ancestor]) -> Origin {
        Origin(pid: 99, arguments: [], started: nil, executable: executable, ancestors: ancestors + [launchd],
               coalition: nil)
    }

    /// claude ← disclaimer ← Claude (measured 2026-10-21): the app, not its
    /// helper nearest the process.
    @Test func usedByIsTheOutermostAppAncestor() {
        let o = origin("/Users/u/Library/Application Support/Claude/claude-code/2.1.299/x/claude.app/Contents/MacOS/claude", [
            .init(pid: 30, path: "/bin/zsh", name: "-zsh"),
            .init(pid: 20, path: "/Users/u/Library/Application Support/Claude/claude-code/2.1.299/x/claude.app/Contents/MacOS/claude", name: "claude"),
            .init(pid: 11, path: "/Applications/Claude.app/Contents/Helpers/disclaimer", name: "disclaimer"),
            .init(pid: 10, path: "/Applications/Claude.app/Contents/MacOS/Claude", name: "Claude",
                  app: "/Applications/Claude.app", appBundleID: "com.anthropic.claudefordesktop"),
        ])
        #expect(o.usedBy?.pid == 10)
    }

    /// iTerm's session server lives outside its bundle; iTerm still is the app.
    @Test func anAppAboveANonAppHelperIsStillTheApp() {
        let o = origin("/bin/sleep", [
            .init(pid: 20, path: "/Users/u/Library/Application Support/iTerm2/iTermServer-3.7.6", name: "iTermServer-3.7.6"),
            .init(pid: 10, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2", name: "iTerm2", app: "/Applications/iTerm.app"),
        ])
        #expect(o.usedBy?.pid == 10)
    }

    /// No app in the chain: the top of it. screen runs each window through
    /// `login`, so the nearest is a shell or login (measured 2026-10-21).
    @Test func withoutAnAppTheTopOfTheChainUsesIt() {
        let o = origin("/bin/sleep", [
            .init(pid: 40, path: "/bin/bash", name: "bash"),
            .init(pid: 30, path: "/usr/bin/login", name: "login"),
            .init(pid: 20, path: "/usr/bin/screen", name: "SCREEN"),
        ])
        #expect(o.usedBy?.name == "SCREEN")
    }

    /// A tool that sits in a bundle is not an app: the toolchain's git runs
    /// from inside Xcode.app with Xcode not running.
    @Test func aPathInsideABundleIsNotAnApp() {
        let o = origin("/bin/sleep", [
            .init(pid: 40, path: "/Applications/Xcode.app/Contents/Developer/usr/bin/git", name: "git"),
            .init(pid: 20, path: "/opt/homebrew/bin/tmux", name: "tmux"),
        ])
        #expect(o.usedBy?.name == "tmux")
    }

    /// A tool its own binary started is not used by itself.
    @Test func theSameBinaryIsSkipped() {
        let codex = "/u/.codex/packages/standalone/releases/0.162.1/bin/codex"
        let o = origin(codex, [
            .init(pid: 30, path: codex, name: "codex"),
            .init(pid: 20, path: "/opt/homebrew/bin/tmux", name: "tmux"),
        ])
        #expect(o.usedBy?.pid == 20)
    }

    /// Orphaned: launchd is its parent, and nothing uses it.
    @Test func launchdIsNobody() {
        #expect(origin("/x/codex", []).usedBy == nil)
    }

    @Test func coalitionNames() {
        let terminal = Origin.Coalition(name: "application.com.apple.Terminal.1152921500311915999.1152921500311916004", ended: false)
        #expect(terminal.bundleID == "com.apple.Terminal")
        #expect(terminal.label == "com.apple.Terminal")
        let sshd = Origin.Coalition(name: "com.openssh.sshd.85A85D11-69E4-4415-8F52-198133816BE8", ended: true)
        #expect(sshd.bundleID == nil)
        #expect(sshd.label == "com.openssh.sshd")
        let agent = Origin.Coalition(name: "com.duoprobe.sleep", ended: false)
        #expect(agent.label == "com.duoprobe.sleep")
        // launchd's own line wins over the name.
        let lower = Origin.Coalition(name: "application.com.apple.terminal.1.2", ended: false, bundleLine: "com.apple.Terminal")
        #expect(lower.bundleID == "com.apple.Terminal")
        // An AppleScript applet: no bundle identifier, named by its bundle.
        let applet = Origin.Coalition(name: "application.ClaudeWakeHost.app.35196AB7-F8B4-4D5F-966B-B8DEF7C6ADB6",
                                      ended: true, bundleLine: "")
        #expect(applet.bundleID == nil)
        #expect(applet.label == "ClaudeWakeHost")
    }

    func with(_ o: Origin, _ coalition: Origin.Coalition?) -> Origin {
        Origin(pid: o.pid, arguments: [], started: nil, executable: o.executable, ancestors: o.ancestors, coalition: coalition)
    }

    /// The four shapes measured 2026-10-21.
    @Test func summaries() {
        let names = { (id: String) -> String? in ["com.apple.Terminal": "Terminal"][id] }
        // tmux started in Terminal: the chain says tmux, the coalition Terminal.
        let tmux = with(origin("/bin/sleep", [.init(pid: 20, path: "/opt/homebrew/bin/tmux", name: "tmux")]),
                        .init(name: "application.com.apple.Terminal.1.2", ended: false))
        #expect(tmux.summary(appName: names) == "used by tmux · started in Terminal")
        // A daemon an SSH session left behind.
        let daemon = with(origin("/x/codex", []), .init(name: "com.openssh.sshd.85A85D11-69E4-4415-8F52-198133816BE8", ended: true))
        #expect(daemon.summary(appName: names) == "started in com.openssh.sshd (no longer running)")
        // An app no longer installed is named by its identifier.
        let gone = with(origin("/x/codex", []), .init(name: "application.com.example.gone.1.2", ended: true))
        #expect(gone.summary(appName: names) == "started in com.example.gone (no longer running)")
        // Nothing known: the parent.
        #expect(origin("/x/codex", []).summary(appName: names) == "parent: launchd")
        // The app the chain names is not said twice (Terminal's own bundle).
        let terminal = with(origin("/bin/sleep", [
            .init(pid: 20, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", name: "Terminal",
                  app: "/System/Applications/Utilities/Terminal.app", appBundleID: "com.apple.Terminal"),
        ]), .init(name: "application.com.apple.Terminal.1.2", ended: false))
        #expect(terminal.summary(appName: names) == "used by Terminal")
    }

    /// The block as `launchctl print pid/N` printed it on macOS 27.2.
    @Test func parsesTheResourceCoalitionBlock() {
        let output = """
        pid/1450 = {
        \ttype = pid
        \tresource coalition = {
        \t\tID = 1176
        \t\ttype = resource
        \t\tstate = terminated
        \t\tactive count = 0
        \t\tname = com.openssh.sshd.85A85D11-69E4-4415-8F52-198133816BE8
        \t\tbundle ID = 
        \t}
        \tjetsam coalition = {
        \t\tname = something.else
        \t}
        }
        """
        #expect(Origin.parseCoalition(output) == .init(name: "com.openssh.sshd.85A85D11-69E4-4415-8F52-198133816BE8", ended: true, bundleLine: ""))
        // A pid gone by now: launchd prints a stub with no coalition.
        #expect(Origin.parseCoalition("pid/99999 = {\n\tproperties = slain\n}") == nil)
        #expect(Origin.parseCoalition("pid/1 = {\n}") == nil)
    }

    /// On this machine: a child of the test process has the test process as
    /// its parent, and launchd names a coalition for it.
    @Test func readsALiveChild() async throws {
        let (pids, continuation) = AsyncStream.makeStream(of: pid_t.self)
        let child = Task {
            try await ChildProcess.run("/bin/sleep", ["30"], standardOutput: .discard, standardError: .discard,
                                       onCancel: .terminateChild, onLaunch: { continuation.yield($0) })
        }
        defer { child.cancel() }
        var iterator = pids.makeAsyncIterator()
        let pid = try #require(await iterator.next())
        let coalition = await Origin.readCoalition(of: pid)
        let o = try #require(await offCooperativePool { Origin.read(pid: pid, coalition: coalition) })
        #expect(o.executable == "/bin/sleep")
        #expect(o.arguments == ["/bin/sleep", "30"])
        #expect(o.ancestors.first?.pid == getpid())
        #expect(o.ancestors.last?.pid == 1)
        #expect(o.coalition != nil)
    }
}

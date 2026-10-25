import Foundation
import os

/// One time brew's sudo asks for the administrator password.
public struct SudoPasswordRequest: Sendable, Equatable {
    /// The casks the ask is for: those of the run whose upgrade needs sudo.
    public let packages: [String]
    /// 1 for a sudo's first ask; more when the same sudo asks again, which it
    /// does after a wrong password (up to `passwd_tries`, 3 by default,
    /// sudoers(5)). A later sudo in the run — brew calls it for an uninstall
    /// step and for the installer — starts at 1 again: it may ask because its
    /// credential cache ran out (`timestamp_timeout`, 5 minutes by default),
    /// not because anything was wrong.
    public let attempt: Int

    public init(packages: [String], attempt: Int) {
        self.packages = packages
        self.attempt = attempt
    }
}

/// Asks the person for the password; nil when they decline. Cancelled when
/// the run it was asked for is over.
public typealias SudoPasswordPrompt = @Sendable (SudoPasswordRequest) async -> String?

/// The `SUDO_ASKPASS` program for one brew run, and the app's end of it.
///
/// brew runs a pkg's `/usr/sbin/installer` (and its uninstall's receipt
/// removal) under `/usr/bin/sudo`, which with no terminal fails outright unless
/// `SUDO_ASKPASS` is set: then brew passes `-A` (Homebrew 7.0.10
/// `system_command.rb` `sudo_prefix`; `SUDO_ASKPASS` is one of the variables
/// `bin/brew` keeps when it clears the environment), and sudo runs that program
/// as the user and reads the password from its standard output (sudo(8) `-A`).
/// brew can't be run as root instead (`brew.sh` refuses), nor authorized ahead:
/// it resets sudo's credential cache before it runs (`utils/sudo.sh`).
///
/// The program is a shell script in a directory only this user can open
/// (`mkdtemp` under the per-user temporary directory), made for the run and
/// removed after it, next to a Unix-domain socket `s`. It connects with
/// `/usr/bin/nc -U`, sends `ask <its pid> <sudo's pid>`, and prints the line it
/// gets back: the password, or nothing when the connection closes without one.
/// The password passes through the socket and the script's standard output
/// into sudo, and is kept nowhere.
///
/// Who asks is checked, not taken from the line: any process of this user can
/// connect. The kernel names the asking process (`LOCAL_PEERPID`), and the ask
/// counts only when that process's ancestry, walked up through the kernel's
/// parent records, reaches this process through a sudo — askpass → sudo →
/// brew → this app, as brew runs it: our child `bin/brew` execs `brew.sh`,
/// which execs Ruby, which spawns `/usr/bin/sudo` straight from
/// `SystemCommand` (`Process.spawn`), privileged cask steps included
/// (`install_steps.rb` runs them in the parent, not in its sandbox child; all
/// read in Homebrew 7.0.10). Anything else is closed unanswered, with no panel.
/// That sudo, not the pid in the line, is the one the attempt is counted for.
///
/// No password — declined, unusable, or the run over — is the script printing
/// nothing. sudo reads only the output (it doesn't look at the exit status),
/// and an empty read is no password, which it gives up on without asking again
/// (sudo 1.9.17p2 `tgetpass.c` `sudo_askpass`, `pam.c` `converse`, read in the
/// upstream source; Apple's build can't be inspected). After a decline every
/// later ask in the run is answered that way without asking.
///
/// What the ancestry check does not stop, accepted on purpose (security review
/// 2026-10-25, item E): another process of this same user rewriting the script.
/// The directory is 0700, but this user owns it, so such a process can find it
/// (`duo-askpass.*` in the per-user temporary directory) and replace `askpass`
/// with one that also keeps the line it reads. sudo runs whatever is at the
/// path — it checks no owner or mode on an askpass program (sudo(8), and
/// `sudo_askpass` in upstream `tgetpass.c`) — so the replacement is sudo's child
/// and passes the check, and the person sees one ordinary panel. Measured: a
/// sibling process polling every 5 ms swapped the script within 0.065 s of the
/// channel opening and received the password. Not fixed because it adds almost
/// nothing for that attacker: brew itself is in the trusted chain and its tree
/// under `/opt/homebrew` is writable by the same user, so a modified brew can
/// run `sudo -A` with any command and get this same, genuine panel, with no
/// race to win. A signed askpass inside the bundle checked through the peer's
/// audit token would close only the rewrite, not that. Closing both means not
/// handing the administrator password to a chain that runs user-writable code.
enum BrewAskPass {
    /// Whether a program, by the path `proc_pidpath` gives for it, is sudo.
    typealias IsSudo = @Sendable (_ executablePath: String) -> Bool
    static let isSudo: IsSudo = { $0 == "/usr/bin/sudo" }

    /// Run `body` with the environment that points brew's sudo at a fresh
    /// askpass program, answering it with `prompt`. With no prompt — or when
    /// the program can't be made — `body` runs with no environment, and a sudo
    /// fails as it did before there was a prompt.
    static func withChannel<T: Sendable>(
        packages: [String],
        prompt: SudoPasswordPrompt?,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        isSudo: @escaping IsSudo = BrewAskPass.isSudo,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (_ environment: [String: String]) async throws -> T
    ) async throws -> T {
        guard let prompt else { return try await body([:]) }
        let channel: Channel
        do {
            channel = try Channel(packages: packages, prompt: prompt, isSudo: isSudo, in: temporaryDirectory)
        } catch {
            Log.install.error("brew sudo: no askpass program (\(String(describing: error), privacy: .public)); a sudo in this run fails")
            return try await body([:])
        }
        do {
            let result = try await body(["SUDO_ASKPASS": channel.program.path])
            await channel.close()
            return result
        } catch {
            await channel.close()
            throw error
        }
    }

    /// The script. `directory` is quoted for sh: inside single quotes nothing
    /// is special but the quote itself.
    static func script(directory: String) -> String {
        let quoted = "'" + directory.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        return """
        #!/bin/sh
        d=\(quoted)
        r=$(printf 'ask %s %s\\n' "$$" "$PPID" | /usr/bin/nc -U "$d/s") || exit 1
        [ -n "$r" ] || exit 1
        printf '%s\\n' "$r"

        """
    }

    /// A password the script can hand on: one line, no NUL. sudo's own reader
    /// stops at the first CR or LF (`tgetpass.c` `getln`), so one there would
    /// be a different password, and a LF would split the reply.
    static func isUsable(_ password: String) -> Bool {
        !password.isEmpty && !password.utf8.contains { $0 == 0x0A || $0 == 0x0D || $0 == 0x00 }
    }

    /// One `ask <script pid> <sudo pid>` line, or nil.
    static func parseRequest(_ line: Substring) -> (script: String, sudo: String)? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "ask",
              let script = Int32(fields[1]), let sudo = Int32(fields[2])
        else { return nil }
        return (String(script), String(sudo))
    }

    /// How many parents up from the asker the walk looks for this process.
    static let maxAncestry = 32

    /// The sudo `asker` asks under: the nearest ancestor `isSudo` takes for
    /// sudo, when the asker's ancestry reaches `root` (this process) above it.
    /// nil when no sudo stands between the two, when the walk leaves `root`'s
    /// descendants — an ancestor gone, or launchd reached, as a double-forked
    /// process's is — or when it is longer than `maxAncestry`.
    static func sudoAncestor(of asker: pid_t, isSudo: IsSudo, root: pid_t = getpid()) -> pid_t? {
        var pid = asker
        var sudo: pid_t?
        for _ in 0..<maxAncestry {
            guard let parent = parentPID(of: pid) else { return nil }
            if parent == root { return sudo }
            guard parent > 1 else { return nil }
            if sudo == nil, let path = executablePath(of: parent), isSudo(path) { sudo = parent }
            pid = parent
        }
        return nil
    }

    /// The kernel's parent record. `PROC_PIDT_SHORTBSDINFO`, not
    /// `PROC_PIDTBSDINFO`: the latter fails for a process running as root,
    /// which sudo is (measured on macOS 27.2 against root daemons and a setuid
    /// one; the short form answers for them).
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(bitPattern: info.pbsi_ppid)
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(length), as: UTF8.self)
    }

    /// The process at the other end of a connection, as the kernel has it.
    static func peerPID(_ connection: Int32) -> pid_t? {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(connection, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else { return nil }
        return pid
    }

    enum ChannelError: Error {
        case setup(String)
    }

    /// One accepted ask: its connection, which this side closes, and the sudo
    /// it came from.
    struct Ask: Sendable {
        let connection: Int32
        let sudo: pid_t
    }

    /// The accepted connections still open. A connection is closed by
    /// whoever takes it out — the answer, or `closeAll` — so never twice, and
    /// none is let in once the channel is closing.
    final class Connections: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (closing: false, open: Set<Int32>()))

        func admit(_ connection: Int32) -> Bool {
            state.withLock { state in
                guard !state.closing else { return false }
                state.open.insert(connection)
                return true
            }
        }

        func close(_ connection: Int32) {
            if state.withLock({ $0.open.remove(connection) }) != nil { Darwin.close(connection) }
        }

        func closeAll() {
            let open = state.withLock { state in
                state.closing = true
                defer { state.open = [] }
                return state.open
            }
            open.forEach { Darwin.close($0) }
        }
    }

    /// The directory, the socket this side listens on, and the task that
    /// answers accepted asks in order.
    final class Channel: @unchecked Sendable {
        let directory: URL
        let program: URL
        /// Set by `close`: an ask still queued then is answered with no
        /// password, not asked — the run it came from is over.
        private let closing = OSAllocatedUnfairLock(initialState: false)
        private let connections = Connections()
        private let source: DispatchSourceRead
        private let answering: Task<Void, Never>
        private let requests: AsyncStream<Ask>.Continuation

        init(packages: [String], prompt: @escaping SudoPasswordPrompt, isSudo: @escaping IsSudo, in parent: URL) throws {
            var template = Array(parent.appendingPathComponent("duo-askpass.XXXXXX").path.utf8CString)
            guard let made = mkdtemp(&template) else { throw ChannelError.setup("mkdtemp: \(errno)") }
            directory = URL(fileURLWithPath: String(cString: made), isDirectory: true)
            program = directory.appendingPathComponent("askpass")
            let listener: Int32
            do {
                listener = try Self.listen(at: directory.appendingPathComponent("s").path)
                do {
                    try Data(BrewAskPass.script(directory: directory.path).utf8).write(to: program)
                    guard chmod(program.path, 0o700) == 0 else { throw ChannelError.setup("chmod: \(errno)") }
                } catch {
                    Darwin.close(listener)
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }

            let (stream, continuation) = AsyncStream<Ask>.makeStream()
            requests = continuation
            let connections = connections
            source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: DispatchQueue(label: "duo.askpass"))
            source.setCancelHandler { Darwin.close(listener) }
            source.setEventHandler {
                while true {
                    let connection = accept(listener, nil, nil)
                    guard connection >= 0 else { break }
                    if let ask = Self.authenticate(connection, isSudo: isSudo), connections.admit(connection) {
                        continuation.yield(ask)
                    } else {
                        Darwin.close(connection)
                    }
                }
            }
            source.resume()

            let closing = closing
            answering = Task {
                var asks: [pid_t: Int] = [:]
                var declined = false
                for await ask in stream {
                    asks[ask.sudo, default: 0] += 1
                    var answer: String?
                    if !declined, !closing.withLock({ $0 }), !Task.isCancelled {
                        let given = await prompt(SudoPasswordRequest(packages: packages, attempt: asks[ask.sudo]!))
                        if let given, BrewAskPass.isUsable(given), !closing.withLock({ $0 }) {
                            answer = given
                        } else {
                            declined = true
                        }
                    }
                    if let answer { Self.send(answer + "\n", to: ask.connection) }
                    connections.close(ask.connection)
                }
            }
        }

        /// A listening socket at `path`, non-blocking for the accept loop.
        /// The path has to fit `sun_path` whole: cut short, the socket would
        /// be bound where the script never looks.
        private static func listen(at path: String) throws -> Int32 {
            var address = sockaddr_un()
            let bytes = Array(path.utf8)
            let capacity = MemoryLayout.size(ofValue: address.sun_path)
            guard bytes.count < capacity else {
                throw ChannelError.setup("socket path is \(bytes.count) bytes, sun_path holds \(capacity - 1)")
            }
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.prefix(capacity - 1)) }
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw ChannelError.setup("socket: \(errno)") }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, Darwin.listen(fd, 8) == 0,
                  fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0
            else {
                let error = errno
                Darwin.close(fd)
                throw ChannelError.setup("bind/listen: \(error)")
            }
            return fd
        }

        /// The ask on a fresh connection, when it comes from under this run's
        /// sudo (`sudoAncestor`) and reads `ask <pid> <pid>`; nil otherwise,
        /// and nothing is read from a connection that isn't. The read waits at
        /// most 5 s, so a connection that never sends can't hold the queue.
        private static func authenticate(_ connection: Int32, isSudo: IsSudo) -> Ask? {
            _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
            guard let asker = BrewAskPass.peerPID(connection),
                  let sudo = BrewAskPass.sudoAncestor(of: asker, isSudo: isSudo)
            else {
                Log.install.notice("brew sudo: an ask from outside this run's sudo, closed unanswered")
                return nil
            }
            var on: Int32 = 1
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            guard fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK) == 0,
                  setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0,
                  setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0
            else { return nil }
            var line = [UInt8]()
            var byte: UInt8 = 0
            while line.count < 64 {
                guard read(connection, &byte, 1) == 1 else { return nil }
                if byte == UInt8(ascii: "\n") {
                    guard BrewAskPass.parseRequest(Substring(decoding: line, as: UTF8.self)) != nil else { return nil }
                    return Ask(connection: connection, sudo: sudo)
                }
                line.append(byte)
            }
            return nil
        }

        private static func send(_ text: String, to connection: Int32) {
            var bytes = Array(text.utf8)[...]
            while !bytes.isEmpty {
                let written = bytes.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
                guard written > 0 else { return }
                bytes = bytes.dropFirst(written)
            }
        }

        /// Stop answering — a panel still up is closed by the cancel, and its
        /// sudo gets no password — close every connection still open (its
        /// script sees the end with nothing read), and remove the directory.
        /// Waits for the answering task first, so no reply is written to a
        /// descriptor number already closed and reused.
        func close() async {
            closing.withLock { $0 = true }
            answering.cancel()
            requests.finish()
            await answering.value
            source.cancel()
            connections.closeAll()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

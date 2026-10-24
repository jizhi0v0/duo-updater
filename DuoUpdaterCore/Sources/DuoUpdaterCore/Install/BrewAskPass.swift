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
/// removed after it, next to two FIFOs. It writes `ask <its pid> <sudo's pid>`
/// to `request` and reads `response` for the line addressed to its own pid:
/// `<pid> <password>`, or a bare `<pid>` for no password. A line meant for an
/// earlier script that died before reading it is skipped, never taken as an
/// answer. The password passes through the FIFO and the script's standard
/// output into sudo, and is kept nowhere.
///
/// No password — declined, unusable, or the run over — is the script printing
/// nothing. sudo reads only the output (it doesn't look at the exit status),
/// and an empty read is no password, which it gives up on without asking again
/// (sudo 1.9.17p2 `tgetpass.c` `sudo_askpass`, `pam.c` `converse`, read in the
/// upstream source; Apple's build can't be inspected). After a decline every
/// later ask in the run is answered that way without asking.
enum BrewAskPass {
    /// Run `body` with the environment that points brew's sudo at a fresh
    /// askpass program, answering it with `prompt`. With no prompt — or when
    /// the program can't be made — `body` runs with no environment, and a sudo
    /// fails as it did before there was a prompt.
    static func withChannel<T: Sendable>(
        packages: [String],
        prompt: SudoPasswordPrompt?,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (_ environment: [String: String]) async throws -> T
    ) async throws -> T {
        guard let prompt else { return try await body([:]) }
        let channel: Channel
        do {
            channel = try Channel(packages: packages, prompt: prompt, in: temporaryDirectory)
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
        id=$$
        printf 'ask %s %s\\n' "$id" "$PPID" > "$d/request" || exit 1
        while IFS= read -r line; do
          case "$line" in
            "$id "*) printf '%s\\n' "${line#"$id "}"; exit 0 ;;
            "$id") exit 1 ;;
          esac
        done < "$d/response"
        exit 1

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

    enum ChannelError: Error {
        case setup(String)
    }

    /// The directory, its FIFOs held open by this side, and the reader that
    /// answers requests in order.
    final class Channel: @unchecked Sendable {
        let directory: URL
        let program: URL
        /// Set by `close`: a request still queued then is answered with no
        /// password, not asked — the run it came from is over.
        private let closing = OSAllocatedUnfairLock(initialState: false)
        private let requestFD: Int32
        private let responseFD: Int32
        private let source: DispatchSourceRead
        private let answering: Task<Void, Never>
        private let requests: AsyncStream<(script: String, sudo: String)>.Continuation

        init(packages: [String], prompt: @escaping SudoPasswordPrompt, in parent: URL) throws {
            var template = Array(parent.appendingPathComponent("duo-askpass.XXXXXX").path.utf8CString)
            guard let made = mkdtemp(&template) else { throw ChannelError.setup("mkdtemp: \(errno)") }
            directory = URL(fileURLWithPath: String(cString: made), isDirectory: true)
            program = directory.appendingPathComponent("askpass")
            let request = directory.appendingPathComponent("request").path
            let response = directory.appendingPathComponent("response").path
            do {
                guard mkfifo(request, 0o600) == 0, mkfifo(response, 0o600) == 0 else {
                    throw ChannelError.setup("mkfifo: \(errno)")
                }
                try Data(BrewAskPass.script(directory: directory.path).utf8).write(to: program)
                guard chmod(program.path, 0o700) == 0 else { throw ChannelError.setup("chmod: \(errno)") }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
            // Read-write, so neither open waits for the script's end and neither
            // FIFO reads as closed while the run lasts; a reply written before
            // its script opens `response` waits there for it. Non-blocking: the
            // reader drains what is there and the replies are a line each.
            requestFD = open(request, O_RDWR | O_NONBLOCK | O_CLOEXEC)
            responseFD = open(response, O_RDWR | O_NONBLOCK | O_CLOEXEC)
            guard requestFD >= 0, responseFD >= 0 else {
                if requestFD >= 0 { Darwin.close(requestFD) }
                if responseFD >= 0 { Darwin.close(responseFD) }
                try? FileManager.default.removeItem(at: directory)
                throw ChannelError.setup("open: \(errno)")
            }

            let (stream, continuation) = AsyncStream<(script: String, sudo: String)>.makeStream()
            requests = continuation
            let fd = requestFD
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "duo.askpass"))
            source.setCancelHandler { Darwin.close(fd) }
            // Only touched on the source's serial queue.
            var pending = [UInt8]()
            source.setEventHandler {
                var buffer = [UInt8](repeating: 0, count: 256)
                while true {
                    let count = read(fd, &buffer, buffer.count)
                    guard count > 0 else { break }
                    pending += buffer[0..<count]
                }
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    if let ask = BrewAskPass.parseRequest(Substring(line)) { continuation.yield(ask) }
                }
            }
            source.resume()

            let reply = responseFD
            let closing = closing
            answering = Task {
                var asks: [String: Int] = [:]
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
                    let line = Array((answer.map { "\(ask.script) \($0)" } ?? ask.script).utf8) + [UInt8(ascii: "\n")]
                    _ = line.withUnsafeBytes { write(reply, $0.baseAddress, $0.count) }
                }
            }
        }

        /// Stop answering — a panel still up is closed by the cancel, and its
        /// sudo gets no password — unblock a script still reading (its `read`
        /// sees the FIFO's last writer gone), and remove the directory. Waits
        /// for the answering task first, so no reply is written to a
        /// descriptor number already closed and reused.
        func close() async {
            closing.withLock { $0 = true }
            answering.cancel()
            requests.finish()
            await answering.value
            source.cancel()
            Darwin.close(responseFD)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

import Foundation

/// A formula installed from its HEAD (`brew install --HEAD`): built from the tip
/// of its upstream branch, versioned `HEAD-<commit>`.
///
/// `brew outdated` (and so this app) never compares such a keg with upstream.
/// Without `--fetch-HEAD` brew calls it outdated only when the formula's stable
/// version passes the one recorded at install, or its `version_scheme` rises
/// (Homebrew 7.0.8 `Formula#head_version_outdated?`). New commits upstream go
/// unseen, so the row read "up to date" for any HEAD install.
///
/// `--fetch-HEAD` is not run here. On a GitHub repository it asks the API —
/// anonymously unless brew finds a token of its own, where the 60 an hour are
/// shared with this app — and then a second time to rule out an ambiguous short
/// hash; a rate-limited answer falls back, silently, to `git fetch`ing the whole
/// repository (`GitHubGitDownloadStrategy#commit_outdated?`). Handing brew the
/// app's token would put it on curl's command line (`--header "Authorization:
/// token …"`), readable with `ps` by any process of the user's while it runs —
/// measured 2026-10-08 with a fake token. `BrewHeadCheck` asks instead, one
/// request, from this process.
public struct BrewHeadInstall: Sendable, Equatable {
    /// Where its HEAD comes from, which decides how upstream can be asked.
    public enum Upstream: Sendable, Equatable {
        /// `https://github.com/<owner>/<repo>(.git)` — the GitHub API, with the
        /// app's token.
        case github(owner: String, repo: String)
        /// Any other git URL — `git ls-remote`, which reads refs only.
        case git(url: String)
        /// svn, hg, cvs, fossil…: not asked; the user can run `--fetch-HEAD`.
        case other
    }

    /// `full_name` — the name `brew leaves` prints.
    public let name: String
    /// The keg's version, `HEAD-1a2b3c4` (a revision may follow: `HEAD-1a2b3c4_1`).
    public let version: String
    /// The commit it was built from, as the version abbreviates it; nil for a
    /// bare `HEAD` keg, which names none.
    public let commit: String?
    /// The branch the formula's `head` follows; nil for the remote's default.
    public let branch: String?
    public let upstream: Upstream

    public init(name: String, version: String, commit: String?, branch: String?, upstream: Upstream) {
        self.name = name
        self.version = version
        self.commit = commit
        self.branch = branch
        self.upstream = upstream
    }

    /// What updates it, for the user to run.
    public var upgradeCommand: String { "brew upgrade --fetch-HEAD \(name)" }

    /// From one `formulae` entry of `info --json=v2 --installed`; nil unless the
    /// keg in use is a HEAD one. "In use" is the linked keg, else the newest
    /// installed — the one `list --versions` shows last.
    static func parse(_ f: [String: Any]) -> BrewHeadInstall? {
        guard let name = f["full_name"] as? String else { return nil }
        let installed = (f["installed"] as? [[String: Any]])?.compactMap { $0["version"] as? String } ?? []
        guard
            let version = (f["linked_keg"] as? String) ?? installed.last,
            version == "HEAD" || version.hasPrefix("HEAD-")
        else { return nil }
        let head = (f["urls"] as? [String: Any])?["head"] as? [String: Any]
        let url = head?["url"] as? String ?? ""
        let using = head?["using"] as? String
        return BrewHeadInstall(
            name: name, version: version, commit: commit(inVersion: version),
            branch: (head?["branch"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            upstream: upstream(url: url, using: using))
    }

    /// `1a2b3c4` from `HEAD-1a2b3c4` or `HEAD-1a2b3c4_1`; nil for `HEAD`.
    static func commit(inVersion version: String) -> String? {
        guard version.hasPrefix("HEAD-") else { return nil }
        let hex = version.dropFirst("HEAD-".count).prefix { $0.isHexDigit }
        return hex.count >= 7 ? String(hex).lowercased() : nil
    }

    /// GitHub when brew would treat it as GitHub (`GitHubGitDownloadStrategy`: a
    /// git URL on github.com), any other git URL as git, the rest as `.other`.
    /// `using` names a non-git strategy (`:hg`, `:svn`, `:cvs`, `:fossil`…); a
    /// git URL carries none, or `git`.
    static func upstream(url: String, using: String?) -> Upstream {
        if let using, !using.isEmpty, using != "git" { return .other }
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else {
            return .other
        }
        if host == "github.com" || host == "www.github.com" {
            let parts = components.path.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
                return .github(owner: parts[0], repo: repo)
            }
        }
        let scheme = components.scheme?.lowercased()
        let looksGit = url.hasSuffix(".git") || scheme == "git" || using == "git"
            || ["gitlab.com", "codeberg.org", "git.sr.ht", "git.code.sf.net"].contains(host)
            || host.hasPrefix("git.") || host.hasPrefix("gitlab.")
        return looksGit && (scheme == "https" || scheme == "git" || scheme == "http") ? .git(url: url) : .other
    }
}

/// The answer to "is this HEAD install behind its upstream branch?".
public enum BrewHeadCheckResult: Sendable, Equatable {
    /// The branch tip is the installed commit.
    case upToDate
    /// The branch tip has moved on; its commit, abbreviated.
    case behind(latest: String)
    /// No answer — a sentence for the user.
    case failed(String)
}

/// Asks a HEAD install's upstream for its branch tip — one request, made only
/// when the user asks (`BrewHeadInstall` says why not `--fetch-HEAD`).
public enum BrewHeadCheck {

    /// Asks once. GitHub: `GET /repos/<o>/<r>/commits/<branch or HEAD>` with
    /// `Accept: application/vnd.github.sha`, whose body is the full SHA — the
    /// same request brew's `GitHub.last_commit` makes, with the app's token in
    /// the header (through `countedData`, so the Settings ▸ GitHub budget sees
    /// it). Git: `git ls-remote`. A full SHA compared against the keg's
    /// abbreviation needs no second, ambiguity-ruling request: a prefix match on
    /// the tip is the tip.
    public static func check(_ install: BrewHeadInstall) async -> BrewHeadCheckResult {
        await check(
            install, session: .shared, token: { await ChangelogService.gitHubToken() },
            lsRemote: { await lsRemote(url: $0, branch: $1) })
    }

    /// `check(_:)` with its network seams, for tests.
    static func check(
        _ install: BrewHeadInstall,
        session: URLSession,
        token: @Sendable () async -> String?,
        lsRemote: @Sendable (String, String?) async -> Result<String, LsRemoteError>
    ) async -> BrewHeadCheckResult {
        guard let commit = install.commit else {
            return .failed(String(localized: "The installed copy doesn’t record which commit it was built from."))
        }
        let tip: String
        switch install.upstream {
        case .github(let owner, let repo):
            switch await githubTip(owner: owner, repo: repo, branch: install.branch, session: session, token: await token()) {
            case .success(let sha): tip = sha
            case .failure(let failure): return .failed(failure.message)
            }
        case .git(let url):
            switch await lsRemote(url, install.branch) {
            case .success(let sha): tip = sha
            case .failure(let error): return .failed(error.message)
            }
        case .other:
            return .failed(String(localized: "Its source isn’t a git repository, so it can only be checked with Homebrew."))
        }
        return verdict(installed: commit, tip: tip)
    }

    /// Up to date when the tip starts with the installed abbreviation.
    static func verdict(installed: String, tip: String) -> BrewHeadCheckResult {
        let tip = tip.lowercased()
        return tip.hasPrefix(installed.lowercased()) ? .upToDate : .behind(latest: String(tip.prefix(7)))
    }

    struct Failure: Error { let message: String }

    static func githubTip(
        owner: String, repo: String, branch: String?, session: URLSession, token: String?
    ) async -> Result<String, Failure> {
        // Path components escaped one by one: a branch may hold a slash, which
        // the commits endpoint takes as part of the ref.
        let ref = branch ?? "HEAD"
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/"
            + (ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref))
        else { return .failure(Failure(message: String(localized: "Its upstream address couldn’t be read."))) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
            guard let http = response as? HTTPURLResponse else {
                return .failure(Failure(message: String(localized: "GitHub didn’t answer.")))
            }
            guard http.statusCode == 200 else {
                let error = GitHubReleasesSource.statusError(
                    http.statusCode, rateLimitRemaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
                return .failure(Failure(message: error.localizedDescription))
            }
            let sha = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard sha.count >= 40, sha.allSatisfy(\.isHexDigit) else {
                return .failure(Failure(message: String(localized: "GitHub didn’t answer with a commit.")))
            }
            return .success(sha)
        } catch {
            return .failure(Failure(message: error.localizedDescription))
        }
    }

    public struct LsRemoteError: Error, Equatable {
        public let message: String
    }

    /// `git ls-remote <url> <ref>` — refs only, a few kilobytes, no checkout.
    ///
    /// Never asks for credentials: `credential.helper` is emptied, so no stored
    /// password for that host (the osxkeychain helper's, say) is sent or unlocked
    /// with a Keychain prompt, and `GIT_TERMINAL_PROMPT=0` stops git asking on a
    /// terminal it doesn't have. A public repository needs neither; a private one
    /// fails, which is the honest answer here.
    public static func lsRemote(
        url: String, branch: String?, git: String? = gitPath()
    ) async -> Result<String, LsRemoteError> {
        guard let git else {
            return .failure(LsRemoteError(message: String(localized: "git isn’t installed, so its upstream can’t be checked here.")))
        }
        let ref = branch.map { "refs/heads/\($0)" } ?? "HEAD"
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"
        env["SSH_ASKPASS"] = "/usr/bin/false"
        do {
            let outcome = try await ChildProcess.run(
                git, ["-c", "credential.helper=", "ls-remote", "--", url, ref],
                environment: env, standardError: .capture,
                deadline: .init(terminateAfter: .seconds(30), killAfter: .seconds(35)),
                onCancel: .terminateChild)
            guard outcome.succeeded, !outcome.timedOut else {
                return .failure(LsRemoteError(message: outcome.timedOut
                    ? String(localized: "Its upstream didn’t answer in time.")
                    : String(localized: "Its upstream couldn’t be reached.")))
            }
            return parseLsRemote(String(decoding: outcome.standardOutput, as: UTF8.self))
                .map { .success($0) } ?? .failure(LsRemoteError(message: String(localized: "Its upstream has no such branch.")))
        } catch {
            return .failure(LsRemoteError(message: error.localizedDescription))
        }
    }

    /// The SHA on the first line of `ls-remote` output (`<sha>\t<ref>`).
    static func parseLsRemote(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let sha = line.split(separator: "\t").first.map(String.init) ?? ""
            if sha.count >= 40, sha.allSatisfy(\.isHexDigit) { return sha }
        }
        return nil
    }

    public static let gitCandidates = [
        "/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git",
    ]

    /// A git that runs without asking to install anything: Homebrew's, then the
    /// Command Line Tools'. Not `/usr/bin/git`, whose shim puts up the "install
    /// the command line developer tools" dialog when they are missing.
    public static func gitPath(candidates: [String] = gitCandidates) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

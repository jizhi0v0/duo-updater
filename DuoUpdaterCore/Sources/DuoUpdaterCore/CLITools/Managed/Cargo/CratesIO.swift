import Foundation

/// crates.io's API, for one thing: the repository a crate names
/// (`/api/v1/crates/<name>` → `crate.repository`; tokei's is
/// `https://github.com/XAMPPRocky/tokei.git`, 2026-10-27). Its crawler policy
/// asks for a `User-Agent` that says who is asking and at most one request a
/// second (design §4.9, CARGO-13); the answer is kept per crate for the
/// process, as npm's repository is (`NpmChangelog`).
actor CratesIO {

    static let shared = CratesIO()

    static let userAgent = "DuoUpdater (https://github.com/jizhi0v0/duo-updater)"

    private var repositories: [String: String?] = [:]
    private var last: ContinuousClock.Instant?

    /// The crate's `repository` URL; nil when it names none.
    func repository(of crate: String) async throws -> String? {
        if let known = repositories[crate] { return known }
        // One request a second: each caller takes the next free slot before it
        // waits, so two callers interleaved across the sleep never share one.
        let now = ContinuousClock.now
        let slot = last.map { max(now, $0.advanced(by: .seconds(1))) } ?? now
        last = slot
        if slot > now { try await Task.sleep(until: slot, clock: .continuous) }
        var request = URLRequest(url: URL(string: "https://crates.io/api/v1/crates/")!.appendingPathComponent(crate))
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CLIToolReleaseNotesError.http(status) }
        let repository = Self.repository(data)
        repositories[crate] = .some(repository)
        return repository
    }

    static func repository(_ data: Data) -> String? {
        struct Document: Decodable {
            struct Crate: Decodable { let repository: String? }
            let crate: Crate
        }
        return (try? JSONDecoder().decode(Document.self, from: data))?.crate.repository
    }

    /// `https://github.com/<owner>/<repo>[.git][/…]` → owner and repo; nil for
    /// any other host.
    static func gitHub(_ url: String) -> (owner: String, repo: String)? {
        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased(), host == "github.com" || host == "www.github.com"
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        return parts[0].isEmpty || repo.isEmpty ? nil : (parts[0], repo)
    }
}

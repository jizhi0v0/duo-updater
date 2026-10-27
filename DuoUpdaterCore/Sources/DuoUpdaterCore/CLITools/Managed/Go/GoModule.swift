import Foundation

/// Where a Go module's release notes are: the GitHub repository it lives in,
/// and the tag prefix of its subdirectory (design §4.9, GO-08/16).
///
/// A `github.com/<owner>/<repo>/…` path says so itself. Any other path
/// (`mvdan.cc/gofumpt`) is asked of proxy.golang.org's `@latest`, whose
/// `Origin` names the repository and, for a module in a subdirectory, its
/// `Subdir` — which its tags carry before the version (2026-10-27:
/// `mvdan.cc/gofumpt` → `https://github.com/mvdan/gofumpt`;
/// `github.com/aws/aws-sdk-go-v2/service/s3` → Subdir `service/s3`, Ref
/// `refs/tags/service/s3/v1.114.5`; `golang.org/x/vuln` →
/// `https://go.googlesource.com/vuln`, not GitHub). goproxy.cn's answer has
/// no `Origin`, so proxy.golang.org is asked directly.
enum GoModule {

    struct Origin: Sendable, Equatable {
        let owner: String
        let repo: String
        /// "service/s3/" for a module in that subdirectory; empty at the root.
        let tagPrefix: String
    }

    /// `github.com/<owner>/<repo>[/sub…][/vN]` read off the path; nil for any
    /// other host.
    static func gitHub(path module: String) -> Origin? {
        let parts = module.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "github.com" else { return nil }
        var rest = Array(parts.dropFirst(3))
        // A major version suffix is part of the path, not of the tag.
        if let last = rest.last, isMajorSuffix(last) { rest.removeLast() }
        return Origin(owner: parts[1], repo: parts[2], tagPrefix: rest.isEmpty ? "" : rest.joined(separator: "/") + "/")
    }

    static func isMajorSuffix(_ element: String) -> Bool {
        element.range(of: #"^v[0-9]+$"#, options: .regularExpression) != nil
    }

    /// The module path as the proxy protocol spells it: every capital
    /// `!`-escaped, `BurntSushi` → `!burnt!sushi`.
    static func escaped(_ module: String) -> String {
        module.map { $0.isUppercase ? "!" + $0.lowercased() : String($0) }.joined()
    }

    /// The `Origin` of proxy.golang.org's `@latest`, as an `Origin` here; nil
    /// when it names no GitHub repository.
    static func origin(_ data: Data) -> Origin? {
        struct Latest: Decodable {
            struct Source: Decodable {
                let URL: String?
                let Subdir: String?
            }
            let Origin: Source?
        }
        guard let source = (try? JSONDecoder().decode(Latest.self, from: data))?.Origin, let url = source.URL,
              let repository = CratesIO.gitHub(url)
        else { return nil }
        let subdir = (source.Subdir ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Origin(owner: repository.owner, repo: repository.repo, tagPrefix: subdir.isEmpty ? "" : subdir + "/")
    }

    static func origin(of module: String) async throws -> Origin? {
        if let origin = gitHub(path: module) { return origin }
        guard let url = URL(string: "https://proxy.golang.org/\(escaped(module))/@latest") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CLIToolReleaseNotesError.http(status) }
        return origin(data)
    }
}

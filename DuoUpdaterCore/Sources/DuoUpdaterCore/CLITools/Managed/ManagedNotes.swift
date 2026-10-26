import Foundation

/// A managed row's release notes, read from where its adapter said they are
/// (`ManagedItem.NotesSource`): a repository's GitHub Releases, or a PyPI
/// project whose project URLs name one (`ProjectURLRepo`).
enum ManagedNotes {

    static func fetch(_ notes: ManagedItem.NotesSource?, force: Bool) async throws -> Changelog {
        switch notes {
        case .gitHubReleases(let owner, let repo, let tagPrefix)?:
            return try await gitHubReleases(owner: owner, repo: repo, tagPrefix: tagPrefix, force: force)
        case .pypiProject(let project)?:
            let data = try await PyPIProject.fetch(project)
            guard let document = PyPIProject.parse(data),
                  let repository = ProjectURLRepo.repository(document.projectURLs, project: project)
            else { return Changelog(entries: []) }
            return try await gitHubReleases(owner: repository.owner, repo: repository.repo, tagPrefix: "", force: force)
        default:
            return Changelog(entries: [])
        }
    }

    /// A tag of another product in the same repository (`tagPrefix`) is never
    /// read as this item's.
    static func gitHubReleases(owner: String, repo: String, tagPrefix: String, force: Bool) async throws -> Changelog {
        let source = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=30")!
        let pattern = tagPrefix.isEmpty ? nil : "^" + NSRegularExpression.escapedPattern(for: tagPrefix) + "v?(\\d.*)$"
        return try await DenoChangelog.gitHubReleases(source, force: force, session: .updates) { data in
            StructuredChangelogDecoder.decode(
                String(decoding: data, as: UTF8.self), format: .gitHubReleases, channel: nil, maxEntries: nil,
                tagPattern: pattern)
        }
    }
}

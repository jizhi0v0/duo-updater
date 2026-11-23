import Foundation

/// A bounded GitHub download with shared traffic accounting and credential fallback.
enum CLIGitHubDownload {
    struct BodyTooLarge: LocalizedError {
        var errorDescription: String? { "The GitHub download exceeded its size limit." }
    }

    static func get(_ url: URL, purpose: RequestPurpose, force: Bool, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = purpose == .install ? 120 : 15
        request.httpShouldHandleCookies = false
        let credentials = GitHubCredentials.current
        let generation = credentials.requestGeneration()
        if url.host == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if !credentials.isRejected(generation: generation), let token = await ChangelogService.gitHubToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        for _ in 0..<2 {
            let (bytes, response) = try await URLSession.updates.countedBytes(for: request, purpose: purpose)
            if GitHubCredentials.isRejection(of: request, response) {
                credentials.recordRejection(generation: generation)
                request = GitHubCredentials.anonymous(request)
                continue
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let remaining = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-RateLimit-Remaining")
                throw CLIToolReleaseNotesError.status(code, rateLimitRemaining: remaining, url: url)
            }
            guard http.expectedContentLength <= limit else { throw BodyTooLarge() }
            var body = Data()
            if http.expectedContentLength > 0 { body.reserveCapacity(Int(http.expectedContentLength)) }
            for try await byte in bytes {
                guard body.count < limit else { throw BodyTooLarge() }
                body.append(byte)
            }
            return body
        }
        throw CLIToolReleaseNotesError.http(401)
    }
}

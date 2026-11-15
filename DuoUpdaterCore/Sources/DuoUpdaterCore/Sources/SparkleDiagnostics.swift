import Foundation

extension SparkleAppcastSource {
    /// Read the production feed without an installed copy's local licence
    /// window. Public unattended audits inspect what the vendor publishes;
    /// they must not inherit the runner user's subscription preferences.
    public func probeDiagnostic(for app: InstalledApp) async -> ProbeOutcome {
        let started = Date()
        func answer(_ remote: RemoteVersion? = nil, failure: ProbeFailure? = nil,
                    status: Int? = nil) -> ProbeOutcome {
            ProbeOutcome(
                recipeID: "sparkle:\(app.bundleID ?? "?"):\(app.releaseChannel.rawValue)",
                bundleID: app.bundleID ?? "?", channel: app.releaseChannel,
                remote: remote, failure: failure, httpStatus: status,
                elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
        }
        let source = SparkleAppcastSource(
            session: session, loginWalls: loginWalls, subscriptionWindow: { _ in nil })
        do {
            guard let remote = try await source.latestVersion(for: app) else {
                return answer(failure: .versionPatternNoMatch(sampleBytes: 0))
            }
            return answer(remote)
        } catch let error as OSWindowRefused {
            return answer(failure: .outsideVendorOSWindow(error.refusal, release: error.release))
        } catch SparkleError.badStatus(let code) {
            return answer(failure: .httpStatus(code), status: code)
        } catch let error as URLError {
            return answer(failure: .transport(urlErrorCode: error.code.rawValue,
                                              error.localizedDescription))
        } catch {
            // A successful response that is not an appcast, including a refused
            // signed feed, is a feed defect rather than a network outage. Never
            // copy the response body into the public report.
            return answer(failure: .archiveExtractionFailed(error.localizedDescription))
        }
    }
}

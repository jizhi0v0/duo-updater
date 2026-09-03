import Foundation

/// Onboarding helper for `AlcoveUpdateSource`: turns the one secret a user can
/// actually supply — their Alcove **license key** — into the per-machine
/// `instance_id` the licensed update API needs, without a packet capture.
///
/// Why this is non-trivial: Alcove's API (Lemon-Squeezy-shaped) only hands out a
/// Bearer for an *existing* activation `instance_id`, and that id is sealed inside
/// Alcove's own encrypted Keychain blob (unreadable). The only id-bearing surfaces
/// are `issue-token`/`activate` (which need an id or *create* one) — there is no
/// read-only "resolve my instance by name" call (`validate` confirms the license
/// but returns `instance: null`). So we recover this Mac's real id indirectly:
///
///   1. `validate {license_key}` → is the license active, and `usage`/`limit`.
///   2. If a slot is free, `issue-token {license_key, instance_name, instance_model}`
///      **activates a throwaway instance** for this Mac and returns the full
///      `instances[]` list (verified 2026-06-17 against the live API).
///   3. The list now holds two entries with this Mac's name+model: Alcove's own
///      activation and our throwaway. The one whose id ≠ the throwaway's is
///      **Alcove's real instance_id** — we keep that and `deactivate` the throwaway,
///      so the net activation cost is **zero** and we end up sharing Alcove's own id
///      (issue-token by id is read-only, so sharing it is fine).
///   4. If no pre-existing entry matches (this Mac was never activated in Alcove),
///      we keep the throwaway as this machine's instance (net +1 slot).
///
/// At the activation limit (`usage == limit`) step 2 fails 403 ("License has reached
/// activation limit"), so there is no non-destructive path — the caller must fall
/// back to a manually supplied instance_id (capture) or the public probe.
///
/// The license key is never logged and only ever sent to `api.tryalcove.com` over
/// HTTPS in a POST body — the same destination Alcove itself uses, no third party.
public struct AlcoveLicenseService: Sendable {
    private static let base = URL(string: "https://api.tryalcove.com")!
    /// Identify honestly — see the note on `AlcoveUpdateSource.userAgent` for why
    /// this no longer impersonates Alcove's own client.
    private static let userAgent = "DuoUpdater/0.1"

    private let session: URLSession
    public init(session: URLSession = .updates) { self.session = session }

    /// Whether a license key is valid, and how many activation slots it has used.
    public struct LicenseInfo: Sendable, Equatable {
        public let active: Bool
        public let usage: Int
        public let limit: Int
        public var atLimit: Bool { usage >= limit }
    }

    /// Outcome of resolving this machine's `instance_id` from a license key.
    public enum ResolveResult: Sendable, Equatable {
        /// Got an id usable for updates. `consumedSlot` is true only in the rare
        /// case where this Mac had no pre-existing Alcove activation, so we kept a
        /// freshly created one (net +1 activation).
        case resolved(instanceID: String, consumedSlot: Bool)
        /// License is at its activation limit — no free slot to bootstrap the
        /// lookup. The caller should ask for a manual instance_id or free a slot.
        case atLimit(usage: Int, limit: Int)
        /// The key was rejected (typo, refunded, deactivated…).
        case invalidLicense
        /// Network/parse failure — try again later.
        case failed(String)
    }

    // MARK: - Public API

    /// Validate a license key (read-only; never activates).
    public func validate(licenseKey: String) async -> LicenseInfo? {
        guard let body = try? await post("/license/validate", ["license_key": licenseKey]),
              let obj = try? JSONDecoder().decode(LicenseResponse.self, from: body)
        else { return nil }
        return LicenseInfo(active: obj.active, usage: obj.usage ?? 0, limit: obj.limit ?? 0)
    }

    /// Resolve this Mac's `instance_id` from the license key alone. `deviceName`
    /// and `deviceModel` are this Mac's identity (ComputerName + `hw.model`), which
    /// the API keys activations on.
    public func resolveInstanceID(
        licenseKey: String, deviceName: String, deviceModel: String
    ) async -> ResolveResult {
        guard let info = await validate(licenseKey: licenseKey) else {
            return .failed("Could not reach the Alcove licensing API.")
        }
        guard info.active else { return .invalidLicense }
        guard !info.atLimit else { return .atLimit(usage: info.usage, limit: info.limit) }

        // Activate a throwaway instance for this Mac → returns the full list.
        guard let body = try? await post(
            "/license/issue-token",
            ["license_key": licenseKey, "instance_name": deviceName, "instance_model": deviceModel],
            allow403: true)
        else { return .failed("Activation request failed.") }

        guard let resp = try? JSONDecoder().decode(IssueTokenResponse.self, from: body) else {
            // A 403 body decodes here as a message, not an instance → treat as limit.
            if let msg = try? JSONDecoder().decode(MessageResponse.self, from: body),
               msg.message.localizedCaseInsensitiveContains("limit") {
                return .atLimit(usage: info.usage, limit: info.limit)
            }
            return .failed("Unexpected activation response.")
        }
        guard let throwaway = resp.instance?.id else { return .failed("Activation returned no instance.") }

        // Recover Alcove's own id: same name+model, different id than the throwaway.
        let own = resp.instances?.first {
            $0.name == deviceName && $0.model == deviceModel && $0.id != throwaway
        }?.id

        if let own {
            // Give the slot back; best-effort with a couple of retries.
            await deactivateWithRetry(licenseKey: licenseKey, instanceID: throwaway)
            return .resolved(instanceID: own, consumedSlot: false)
        } else {
            // No prior activation for this Mac — keep the one we just made.
            return .resolved(instanceID: throwaway, consumedSlot: true)
        }
    }

    /// Release an activation slot. Returns whether it succeeded.
    @discardableResult
    public func deactivate(licenseKey: String, instanceID: String) async -> Bool {
        (try? await post("/license/deactivate", ["license_key": licenseKey, "instance_id": instanceID])) != nil
    }

    // MARK: - Internals

    /// Release the throwaway activation, retrying a few times so a transient
    /// network blip doesn't leak a slot. If all attempts fail the slot is left
    /// occupied (rare); the user can deactivate that device in Alcove. We never log
    /// the id.
    private func deactivateWithRetry(licenseKey: String, instanceID: String) async {
        for _ in 0..<3 {
            if await deactivate(licenseKey: licenseKey, instanceID: instanceID) { return }
        }
    }

    /// POST a JSON body and return the response data for a 2xx (and 403 when
    /// `allow403`, so the limit message can be inspected). nil otherwise.
    private func post(_ path: String, _ json: [String: String], allow403: Bool = false) async throws -> Data? {
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
        guard let http = response as? HTTPURLResponse else { return nil }
        if (200..<300).contains(http.statusCode) { return data }
        if allow403 && http.statusCode == 403 { return data }
        return nil
    }
}

// MARK: - Wire types

private struct LicenseResponse: Decodable {
    let active: Bool
    let usage: Int?
    let limit: Int?
}

private struct MessageResponse: Decodable { let message: String }

private struct IssueTokenResponse: Decodable {
    let token: String?
    let instance: Instance?
    let instances: [Instance]?
    struct Instance: Decodable, Equatable {
        let id: String
        let name: String
        let model: String?
    }
}

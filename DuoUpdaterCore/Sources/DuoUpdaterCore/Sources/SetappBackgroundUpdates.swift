import AppKit
import Foundation

/// Owns only the cold client launched by an automatic refresh. Its window can
/// appear behind the foreground app; any activation hands the instance to the
/// user permanently. A manual row action deliberately does not use this owner.
@MainActor
public final class SetappBackgroundUpdates {
    public static let shared = SetappBackgroundUpdates()
    public private(set) var isManaging = false

    public init() {}

    /// Returns immediately; the normal check round never waits for installation.
    public func start(client: URL, targets: [URL: VersionSide]) {
        guard !isManaging, !targets.isEmpty, Self.clients.isEmpty else { return }
        // A check result can have become stale while the round was in flight.
        let pending = targets.filter { path, target in
            guard let disk = Self.version(at: path) else { return false }
            return VersionComparator.isNewer(target, than: disk)
        }
        guard !pending.isEmpty else { return }
        isManaging = true
        Task {
            await run(client: client, targets: pending)
            isManaging = false
        }
    }

    private static var clients: [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: SetappAutomation.clientBundleIdentifier)
    }

    private func run(client: URL, targets: [URL: VersionSide]) async {
        let observation = Observation()
        defer { observation.stop() }
        // Observe before launching, so activation/termination during the await
        // cannot be lost. Recheck after installing the observers as well.
        guard Self.clients.isEmpty else { return }
        let requestedAt = Date()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        // `hides=true` makes Setapp 3.58.0 activate itself (VM verified).
        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: client, configuration: configuration)
        } catch {
            Log.source.error("Setapp: background launch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let identity = Self.identity(app), identity.launchedAt >= requestedAt,
              app.bundleURL?.standardizedFileURL == client.standardizedFileURL else {
            Log.source.notice("Setapp: leaving client running — launch ownership is uncertain")
            return
        }
        Log.source.info("Setapp: managing background client \(identity.pid, privacy: .public)")
        let clock = ContinuousClock()
        let started = clock.now
        var policy = SetappUpdateSessionPolicy(targets: Set(targets.keys))
        var generation = 0
        while !Task.isCancelled {
            let prefs = UserDefaults(suiteName: SetappSubscription.defaultsDomain)?
                .persistentDomain(forName: SetappSubscription.defaultsDomain)
            let sessions = SetappActiveSessions.read(prefs, now: Date())
            let current = NSRunningApplication(processIdentifier: identity.pid)
            let sameInstance = !app.isTerminated && current.flatMap(Self.identity) == identity
                && !observation.terminated.contains(identity.pid)
                && Self.clients.allSatisfy { Self.identity($0) == identity }
            let adopted = app.isActive || current?.isActive == true
                || NSWorkspace.shared.frontmostApplication?.processIdentifier == identity.pid
                || observation.activated.contains(identity.pid)
            let completed = Set(targets.compactMap { path, target -> URL? in
                guard let disk = Self.version(at: path),
                      VersionComparator.hasReached(target, disk: disk) else { return nil }
                return path
            })
            let activity = generation != observation.generation
            generation = observation.generation
            let decision = policy.sample(
                at: started.duration(to: clock.now), sameInstance: sameInstance, adopted: adopted,
                observationValid: sessions != nil && observation.valid,
                busy: !(sessions ?? []).isEmpty || !observation.active.isEmpty,
                witnessedSession: observation.witnessedSession || !(sessions ?? []).isEmpty,
                activity: activity, completed: completed)
            switch decision {
            case .wait:
                try? await Task.sleep(for: .seconds(1))
            case .relinquish:
                Log.source.notice("Setapp: stopped managing client \(identity.pid, privacy: .public) — in use, replaced or state uncertain")
                return
            case .quit:
                // No await between the final identity/use checks and this
                // request. Never look up a replacement by bundle ID, force quit,
                // retry a declined quit, or terminate SetappAgent.
                guard !app.isTerminated, !app.isActive,
                      !observation.activated.contains(identity.pid),
                      !observation.terminated.contains(identity.pid),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier != identity.pid,
                      NSRunningApplication(processIdentifier: identity.pid).flatMap(Self.identity) == identity
                else { return }
                let accepted = app.terminate()
                Log.source.info("Setapp: idle client \(identity.pid, privacy: .public) quit requested; accepted=\(accepted)")
                return
            }
        }
    }

    private static func identity(_ app: NSRunningApplication) -> SetappProcessIdentity? {
        guard app.processIdentifier > 0, let date = app.launchDate else { return nil }
        return SetappProcessIdentity(pid: app.processIdentifier, launchedAt: date)
    }

    private static func version(at bundle: URL) -> VersionSide? {
        guard let data = try? Data(contentsOf: BundleLayout.infoPlistURL(for: bundle)),
              let fields = (try? PropertyListSerialization.propertyList(from: data, format: nil))
                as? [String: Any] else { return nil }
        let side = VersionSide(marketing: VersionSide.plistVersionField(fields["CFBundleShortVersionString"]),
                               build: VersionSide.plistVersionField(fields["CFBundleVersion"]))
        return side.isEmpty ? nil : side
    }

    @MainActor
    private final class Observation {
        var activated: Set<Int32> = []
        var terminated: Set<Int32> = []
        var active: Set<String> = []
        var witnessedSession = false
        var valid = true
        var generation = 0
        private var workspaceTokens: [NSObjectProtocol] = []
        private var distributedTokens: [NSObjectProtocol] = []

        init() {
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceTokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.bundleIdentifier == SetappAutomation.clientBundleIdentifier else { return }
                    let pid = app.processIdentifier
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if name == NSWorkspace.didActivateApplicationNotification { self.activated.insert(pid) }
                        else { self.terminated.insert(pid) }
                    }
                })
            }
            for name in ["com.setapp.apps-refresh-will-start", "com.setapp.apps-refresh-did-end"] {
                distributedTokens.append(DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(name), object: nil, queue: .main
                ) { [weak self] note in
                    let raw = note.userInfo?["com.setapp.apps-refresh-process-id"] as? String
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard let raw, let id = UUID(uuidString: raw)?.uuidString else { self.valid = false; return }
                        self.generation += 1
                        if name.hasSuffix("will-start") {
                            self.witnessedSession = true
                            self.active.insert(id)
                        } else { self.active.remove(id) }
                    }
                })
            }
        }

        func stop() {
            for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            for token in distributedTokens { DistributedNotificationCenter.default().removeObserver(token) }
        }
    }
}

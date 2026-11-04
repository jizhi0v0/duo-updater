import Foundation

/// A bounded idle window, not a download timeout. Only a witnessed refresh or
/// every expected version landing makes an automatic quit eligible.
struct SetappUpdateSessionPolicy {
    enum Decision: Equatable { case wait, quit, relinquish }

    static let idle: Duration = .seconds(30)
    static let maximum: Duration = .seconds(600)

    private var remaining: Set<URL>
    private var idleSince: Duration = .zero
    private var witnessedSession = false

    init(targets: Set<URL>) { remaining = targets }

    mutating func sample(
        at elapsed: Duration, sameInstance: Bool, adopted: Bool,
        observationValid: Bool, busy: Bool, witnessedSession: Bool,
        activity: Bool, completed: Set<URL>
    ) -> Decision {
        guard sameInstance, !adopted, observationValid,
              elapsed < Self.maximum else { return .relinquish }
        self.witnessedSession = self.witnessedSession || witnessedSession
        let newlyCompleted = remaining.intersection(completed)
        remaining.subtract(newlyCompleted)
        if busy || activity || !newlyCompleted.isEmpty { idleSince = elapsed }
        guard !busy else { return .wait }
        guard self.witnessedSession || remaining.isEmpty else {
            // No usable witness: stop managing, rather than assume a silent
            // downloader finished or extend this session forever.
            return elapsed >= Self.idle ? .relinquish : .wait
        }
        return elapsed - idleSince >= Self.idle ? .quit : .wait
    }
}

struct SetappProcessIdentity: Equatable, Hashable {
    let pid: Int32
    let launchedAt: Date
}

/// Remember every observed session until its matching end notification. A
/// preference disappearing can be Setapp expiring an old marker mid-download.
struct SetappRefreshActivity {
    private(set) var active: Set<String> = []
    private(set) var witnessedSession = false
    private var ended: Set<String> = []

    mutating func begin(_ id: String) {
        witnessedSession = true
        ended.remove(id)
        active.insert(id)
    }

    mutating func end(_ id: String) {
        ended.insert(id)
        active.remove(id)
    }

    mutating func include(snapshot: Set<String>) {
        witnessedSession = witnessedSession || !snapshot.isEmpty
        // A delayed preference read must not resurrect an already-ended UUID.
        active.formUnion(snapshot.subtracting(ended))
    }
}

/// The framework stores dates under environment-prefixed keys. An old or
/// malformed marker is uncertainty, not permission to quit: Setapp itself
/// expires markers after 300 seconds, even if work might still be running.
enum SetappActiveSessions {
    static func read(_ defaults: [String: Any]?, now: Date) -> Set<String>? {
        guard let defaults else { return nil }
        var sessions: Set<String> = []
        for (key, value) in defaults where key.contains("ActiveRefreshSession_") {
            guard let date = value as? Date,
                  (0..<300).contains(now.timeIntervalSince(date)),
                  let id = UUID(uuidString: String(key.suffix(36))) else { return nil }
            sessions.insert(id.uuidString)
        }
        return sessions
    }
}

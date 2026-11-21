import Foundation

/// A short, bounded retry window for each app seen while Sparkle stages it.
/// An ordinary sweep can settle a row or add another row to watch. It can't
/// spend a retry or push an existing deadline out by starting the timer over.
public struct StagingRecheck {
    public struct Sweep {
        fileprivate let generation: UInt64
        fileprivate let retryStartedAt: ContinuousClock.Instant?
    }

    private struct Retry {
        var attempt = 0
        var deadline: ContinuousClock.Instant?
    }

    private static let delays: [Duration] = [
        .seconds(1), .seconds(1), .seconds(2), .seconds(2), .seconds(4), .seconds(4),
    ]

    private var generation: UInt64 = 0
    private var retries: [String: Retry] = [:]

    public init() {}

    /// Includes exhausted rows so later sweeps cannot restart their budget.
    public var unsettledIDs: Set<String> { Set(retries.keys) }
    public var deadline: ContinuousClock.Instant? { retries.values.compactMap(\.deadline).min() }

    public mutating func begin(retry: Bool, at now: ContinuousClock.Instant) -> Sweep {
        generation &+= 1
        return Sweep(generation: generation, retryStartedAt: retry ? now : nil)
    }

    public func isCurrent(_ sweep: Sweep) -> Bool { sweep.generation == generation }

    public mutating func complete(
        _ sweep: Sweep, unsettled: Set<String>, at now: ContinuousClock.Instant
    ) {
        guard isCurrent(sweep) else { return }
        retries = retries.filter { unsettled.contains($0.key) }
        for id in unsettled {
            guard var retry = retries[id] else {
                retries[id] = Retry(deadline: now.advanced(by: Self.delays[0]))
                continue
            }
            guard let started = sweep.retryStartedAt, let due = retry.deadline, due <= started
            else { continue }
            retry.attempt += 1
            retry.deadline = retry.attempt < Self.delays.count
                ? now.advanced(by: Self.delays[retry.attempt]) : nil
            retries[id] = retry
        }
    }
}

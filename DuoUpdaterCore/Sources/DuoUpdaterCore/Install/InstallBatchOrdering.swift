import Foundation

/// Ordering for "Update All": the batch runs in list order, which is
/// alphabetical by app name — so a 400 MB Office update can occupy a slot for
/// ten minutes while nine 20 MB updates queue behind it. Shortest-job-first
/// (by download size) minimizes how long the whole wave takes to finish.
public enum InstallBatchOrdering {

    /// Sort `targets` by declared download size, smallest first.
    ///
    /// An unknown size is treated as NEUTRAL, not as "tiny" or "huge": rows
    /// without a size sort next to the median known size, so they neither jump
    /// the queue (delaying a known-small update behind a possibly-enormous
    /// one) nor get starved behind the largest. The sort is stable — ties
    /// (including every tie an unknown row makes with the median) keep the
    /// caller's original order.
    public static func sortByDownloadSize(_ targets: [UpdateResult]) -> [UpdateResult] {
        let known = targets.compactMap { $0.remote?.downloadSize }
        guard !known.isEmpty else { return targets }
        let median = known.sorted()[known.count / 2]
        return targets.enumerated().sorted { lhs, rhs in
            let l = lhs.element.remote?.downloadSize ?? median
            let r = rhs.element.remote?.downloadSize ?? median
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
    }
}

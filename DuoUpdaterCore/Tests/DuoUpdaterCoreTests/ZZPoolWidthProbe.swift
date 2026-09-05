import Testing
import Foundation

@Suite struct ZZPoolWidthProbe {
    /// Eight CPU-bound tasks. With a full-width pool they overlap; with
    /// LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 (width 1) they must serialise, so the
    /// wall time is ~8x one task instead of ~8/cores.
    @Test func measurePoolWidth() async {
        func spin(_ ms: Double) { let t = Date(); while -t.timeIntervalSinceNow < ms / 1000 {} }
        let one = Date(); spin(200); let single = -one.timeIntervalSinceNow

        let t0 = Date()
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { spin(200) } }
        }
        let wall = -t0.timeIntervalSinceNow
        let strict = ProcessInfo.processInfo.environment["LIBDISPATCH_COOPERATIVE_POOL_STRICT"] ?? "unset"
        print(String(format: "PROBE strict=%@ cores=%d single=%.3fs wall8=%.3fs ratio=%.1f",
                     strict, ProcessInfo.processInfo.activeProcessorCount, single, wall, wall / single))
    }
}

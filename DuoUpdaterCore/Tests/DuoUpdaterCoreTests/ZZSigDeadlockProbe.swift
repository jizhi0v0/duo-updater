import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite struct ZZSigDeadlockProbe {
    @Test func concurrentSignatureChecksOnANarrowPool() async {
        let apps = ["/Applications/Firefox.app", "/Applications/Google Chrome.app",
                    "/Applications/Alcove.app", "/Applications/AppCleaner.app"]
            .filter { FileManager.default.fileExists(atPath: $0) }
        let n = ProcessInfo.processInfo.environment["SIG_FANOUT"].flatMap { Int($0) } ?? 3
        print("PROBE cores=\(ProcessInfo.processInfo.activeProcessorCount) fanout=\(n) apps=\(apps.count)")
        let t0 = Date()
        await withTaskGroup(of: Void.self) { g in
            for i in 0..<n {
                let path = apps[i % max(apps.count, 1)]
                g.addTask {
                    // Exactly what VendorInstaller.apply does from an async context.
                    try? SignatureVerifier.verifyCodeSignature(appAt: URL(fileURLWithPath: path))
                    print("PROBE done \(i) \(String(format: "%.2fs", -t0.timeIntervalSinceNow))")
                }
            }
        }
        print("PROBE all finished in \(String(format: "%.2fs", -t0.timeIntervalSinceNow))")
    }
}

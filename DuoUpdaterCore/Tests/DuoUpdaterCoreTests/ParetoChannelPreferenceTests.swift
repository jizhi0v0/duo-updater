import Foundation
import Testing
@testable import DuoUpdaterCore

struct ParetoChannelPreferenceTests {
    @Test func installedVersionSelectsItsOwnPreferenceAndTheWatcherNoticesEitherSwitch() throws {
        let domain = "test.pareto-channel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var fingerprints = Set<String>()

        for legacy in [false, true] {
            for current in [false, true] {
                defaults.set(legacy, forKey: "betaChannel")
                defaults.set(current, forKey: "showBeta")
                defaults.synchronize()
                fingerprints.insert(niteo_co_Pareto.preferenceFingerprint(domain: domain))
                for version in [nil, "0.0.13", "0.0.18"] {
                    #expect(niteo_co_Pareto.resolveCurrent(installedVersion: version, domain: domain).channel == .stable)
                }
                for version in ["0.0.19", "v1.7.74", "1.9.0"] {
                    #expect(niteo_co_Pareto.resolveCurrent(installedVersion: version, domain: domain).channel
                        == (legacy ? .beta : .stable))
                }
                for version in ["1.9.1", "1.9.3", "v1.22.0", "1.50.0"] {
                    #expect(niteo_co_Pareto.resolveCurrent(installedVersion: version, domain: domain).channel
                        == (current ? .beta : .stable))
                }
            }
        }
        #expect(fingerprints.count == 4)
    }
}

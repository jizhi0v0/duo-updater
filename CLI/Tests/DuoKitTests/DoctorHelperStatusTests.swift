import Foundation
import Testing
@testable import DuoKit

/// `duo doctor` prints what `launchctl print` answered whether or not its task was
/// cancelled, so the read runs to completion.
@Suite struct DoctorHelperStatusTests {

    /// Mutation: `.terminateChild` in `Doctor.exitsZero` → false, "not registered"
    /// for a helper that is.
    @Test func aCancelledStatusReadStillAnswers() async {
        let task = Task { () async -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Doctor.exitsZero("/bin/sh", ["-c", "sleep 0.2; exit 0"])
        }
        #expect(await task.value)
    }
}

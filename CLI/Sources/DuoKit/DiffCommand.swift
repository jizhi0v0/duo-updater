import Foundation
import DuoUpdaterCore

/// `duo diff <old> <new>`. The comparison lives in Core (`BundleDiff`), where the
/// workbench uses it too; this only prints what it returns.
public enum DiffCommand {
    public static func run(old: String, new: String) async -> Int32 {
        switch await BundleDiff.report(old: old, new: new) {
        case .success(let report):
            print(report)
            return 0
        case .failure(let failure):
            FileHandle.standardError.write(Data("duo diff: \(failure.description)\n".utf8))
            return 1
        }
    }
}

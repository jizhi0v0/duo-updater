import Foundation

public enum LeafActivity {
    public static func busy(processes: [ClaudeCodeActivity.Process]) -> Bool {
        processes.contains { process in
            guard let first = process.arguments.first else { return false }
            let name = (first as NSString).lastPathComponent
            if name == "leaf" {
                let command = process.arguments.dropFirst().first(where: { !$0.hasPrefix("-") })
                return (command == "upgrade" || command == "update")
                    && !process.arguments.contains("--check")
            }
            return name == "curl" && process.arguments.contains {
                $0.contains("github.com/DeepanshuMishraa/leaf/releases/")
            }
        }
    }
}

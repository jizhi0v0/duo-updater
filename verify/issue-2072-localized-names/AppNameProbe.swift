import Foundation
import DuoUpdaterCore
var rows: [[String: String]] = []
for languages in [["en-US"], ["zh-Hans-US", "en-US"]] {
    let scanner = AppScanner(locations: [], testflight: TestFlightInventory(macRows: []), preferredLanguages: languages)
    for path in ["/Applications/MediaCenter.app", "/Applications/BaiduNetdisk_mac.app"] {
        guard let app = scanner.scan(bundlesAt: [URL(fileURLWithPath: path)]).first else { fatalError("production scanner did not find " + path) }
        rows.append(["languages": languages.joined(separator: ","), "path": app.path.path, "bundleID": app.bundleID ?? "", "name": app.name, "version": app.shortVersion ?? "", "channel": app.releaseChannel.rawValue])
    }
}
let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))

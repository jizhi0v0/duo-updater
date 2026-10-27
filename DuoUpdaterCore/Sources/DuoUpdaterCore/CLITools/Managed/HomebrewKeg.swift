import Foundation

/// The owner's D5.1, shared: a manager's program is a Homebrew keg's when its
/// link resolves to one of the files the formula itself ships —
/// `<prefix>/Cellar/<formula>/<version>/<one of paths>` — and the keg holds
/// its `INSTALL_RECEIPT.json`. No other file under the keg counts.
enum HomebrewKeg {

    /// The keg's version ("1.18.4" from `1.18.4_1`), nil when `resolved` is
    /// not one of the formula's own `paths` (components below the keg).
    static func version(
        of resolved: String, prefix: String, formula: String, paths: [[String]], contents: (String) -> Data?
    ) -> String? {
        let root = URL(fileURLWithPath: prefix).pathComponents
        let components = URL(fileURLWithPath: resolved).pathComponents
        guard components.count > root.count + 3, Array(components.prefix(root.count)) == root,
              components[root.count] == "Cellar", components[root.count + 1] == formula,
              paths.contains(Array(components.dropFirst(root.count + 3)))
        else { return nil }
        let keg = NSString.path(withComponents: Array(components.prefix(root.count + 3)))
        guard contents(keg + "/INSTALL_RECEIPT.json") != nil else { return nil }
        var version = components[root.count + 2]
        if let underscore = version.lastIndex(of: "_"), version[version.index(after: underscore)...].allSatisfy(\.isNumber) {
            version = String(version[..<underscore])
        }
        return version
    }
}

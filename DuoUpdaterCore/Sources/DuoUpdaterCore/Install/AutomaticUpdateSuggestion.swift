import Foundation

/// A first answer to "may this running app be quit for an update?", read from
/// the bundle alone, for the setup guide that sorts hundreds of apps at once.
/// The user confirms every one; this only decides which box starts ticked.
///
/// Suggested: apps that say they can be quit without losing anything — a
/// menu-bar app (`LSUIElement`, `LSBackgroundOnly`), or one that lets macOS
/// end it on its own (`NSSupportsAutomaticTermination`,
/// `NSSupportsSuddenTermination`, Apple's Information Property List keys).
///
/// Not suggested, whatever else they declare: apps carrying a network
/// extension (VPN, proxy, filter), a File Provider extension (sync) or a system
/// extension. Quitting those drops a connection or interrupts a sync, which no
/// save prompt guards. Nor an input method: it is a menu-bar process, but
/// quitting it takes away the keyboard layout someone may be typing with.
/// And every other app: it has windows, so it may hold work only its own
/// quit prompt would protect.
public enum AutomaticUpdateSuggestion: Equatable, Sendable {
    case suggested(Reason)
    case notSuggested(Reason)

    public enum Reason: Equatable, Sendable {
        case menuBarApp
        case declaresSafeTermination
        case networkExtension
        case fileSync
        case systemExtension
        case inputMethod
        case windowedApp
    }

    public var isSuggested: Bool {
        if case .suggested = self { return true }
        return false
    }

    public static func classify(bundle: URL) -> AutomaticUpdateSuggestion {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
        let extensionPoints = extensionPoints(in: contents.appendingPathComponent("PlugIns", isDirectory: true))
        if extensionPoints.contains(where: { $0.hasPrefix("com.apple.networkextension") }) {
            return .notSuggested(.networkExtension)
        }
        if extensionPoints.contains(where: { $0.hasPrefix("com.apple.fileprovider") }) {
            return .notSuggested(.fileSync)
        }
        if UpdatePolicy.isInputMethod(bundle) || info["InputMethodConnectionName"] != nil {
            return .notSuggested(.inputMethod)
        }
        let systemExtensions = contents.appendingPathComponent("Library/SystemExtensions", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(atPath: systemExtensions.path),
           items.contains(where: { $0.hasSuffix(".systemextension") }) {
            return .notSuggested(.systemExtension)
        }
        if flag(info["LSUIElement"]) || flag(info["LSBackgroundOnly"]) {
            return .suggested(.menuBarApp)
        }
        if flag(info["NSSupportsAutomaticTermination"]) || flag(info["NSSupportsSuddenTermination"]) {
            return .suggested(.declaresSafeTermination)
        }
        return .notSuggested(.windowedApp)
    }

    /// Info.plist booleans appear as `true`, `1` or `"YES"` in the wild.
    static func flag(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String: return ["yes", "true", "1"].contains(string.lowercased())
        default: return false
        }
    }

    static func extensionPoints(in plugIns: URL) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: plugIns.path) else { return [] }
        return items.filter { $0.hasSuffix(".appex") }.compactMap { name in
            let plist = plugIns.appendingPathComponent(name).appendingPathComponent("Contents/Info.plist")
            let info = NSDictionary(contentsOf: plist) as? [String: Any]
            return (info?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        }
    }
}

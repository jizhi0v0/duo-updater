import Foundation

enum RexChannel {
    static let bundleID = "com.superlogical.rex"
    static let preferenceKey = "RexAppUpdateChannel"
    static let previewFeed = URL(string: "https://blob.superlogical.com/public/rex-app/preview-arm64/appcast.xml")!
    static let snapshotFeed = URL(string: "https://blob.superlogical.com/public/rex-app/snapshot-arm64/appcast.xml")!

    static func resolveCurrent(declaredFeed: URL?) -> ResolvedChannel? {
        CFPreferencesAppSynchronize(bundleID as CFString)
        let preference = CFPreferencesCopyAppValue(preferenceKey as CFString, bundleID as CFString) as? String
        return resolve(preference: preference, declaredFeed: declaredFeed)
    }

    static func resolve(preference: String?, declaredFeed: URL? = nil) -> ResolvedChannel? {
        // Bind the two observed feeds. Leave other feeds to Sparkle's normal dispatch.
        if let declaredFeed, declaredFeed != previewFeed, declaredFeed != snapshotFeed {
            return nil
        }

        // The watcher has no bundle metadata. Keep an absent preference
        // distinct from either explicit choice so it can observe every toggle.
        switch preference {
        case "preview":
            return ResolvedChannel(channel: .preview, feedOverride: previewFeed)
        case "snapshot":
            return ResolvedChannel(channel: .nightly, feedOverride: snapshotFeed)
        default:
            switch declaredFeed {
            case previewFeed: return ResolvedChannel(channel: .preview, feedOverride: previewFeed)
            case snapshotFeed: return ResolvedChannel(channel: .nightly, feedOverride: snapshotFeed)
            default: return nil
            }
        }
    }
}

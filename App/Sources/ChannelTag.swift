import SwiftUI
import AppKit
import DuoUpdaterCore

/// A small chip naming the app's release channel — Beta / Canary / Dev / …
///
/// Shown only for **non-stable** channels. The point is to explain an otherwise
/// confusing version: a beta install legitimately leads the stable feed (or
/// sits on a parallel build number), so without the tag a row like
/// "6.9.1 → 7.1.1" or "ahead of latest" reads as a glitch. The tag says "you're
/// on this channel — that's why." Stable is the default every app is on, so a
/// "STABLE" chip everywhere would be pure noise; we render nothing for it.
struct ChannelTag: View {
    let channel: ReleaseChannel

    /// The width this tag will claim once laid out, for callers that must budget
    /// row space *before* layout happens (the menu row decides between a wide
    /// progress bar and a compact ring by measuring what the name column needs).
    /// Mirrors `body`'s font and padding — the two have to be changed together.
    static func measuredWidth(for channel: ReleaseChannel) -> CGFloat {
        guard channel != .stable else { return 0 }
        let text = channel.rawValue.uppercased()
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let width = NSAttributedString(
            string: text, attributes: [.font: font, .kern: 0.3]
        ).size().width
        return width + 10   // .padding(.horizontal, 5) on both sides
    }

    var body: some View {
        if channel != .stable {
            Text(channel.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(.orange)
                .help("On the \(channel.rawValue) channel — its version can lead or differ from the stable release.")
        }
    }
}

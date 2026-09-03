import SwiftUI

/// A small green "live" LED dot shown next to an app's name (right after it) when
/// it currently has a running process. Mirrors the convention of a status list (a
/// green dot = active): it lets the user tell at a glance which apps are open, so
/// they know a Restart will interrupt something — or that an in-place update will
/// leave the running instance on old code until they relaunch.
///
/// Rendered only when the app is running; the call sites gate on
/// `model.isRunning(_:)`, so this view itself is always the "on" state. A plain
/// small filled circle — deliberately understated, sitting inline with the name
/// rather than badged onto the icon.
struct RunningIndicator: View {
    /// Diameter of the dot. Small by default to read as an unobtrusive LED;
    /// larger headers pass a bigger size to stay proportional to the title.
    var size: CGFloat = 5

    /// How far down **this dot** has to sit, beside body text, to stop looking high.
    ///
    /// It does not generalize to everything inline, and that is the interesting
    /// part. A 6pt dot is read by its *position* against the x-height band, so
    /// centring it on the text's box leaves it floating. A mark that is nearly as
    /// tall as the letters — the 12pt runtime mark next to it — is read by its
    /// *top and bottom edges* against theirs instead, and nudging that one down
    /// pushes it past the baseline and it reads as sunk. Both were moved together
    /// first; the runtime mark had to be moved back.
    ///
    /// The cause is the same for both: an `HStack` centres its children on the
    /// text's *box*, and the box is taller
    /// than the letters: it runs from the ascender to the descender whether or not
    /// the word has either. The weight of a word sits lower than that, so anything
    /// centred against the box reads as floating.
    ///
    /// 0.5pt, from three measurements that disagree in an informative way. Rendered
    /// at 8× beside "WeChat", the dot's centre of mass sits 0.75pt above the word's.
    /// The font metrics say 1.49pt if the target is the middle of the x-height band
    /// (`(ascender - descender)/2 + descender - xHeight/2` for the 13pt body font).
    /// By eye, 0.5 and 0.75 both look right and 1.0 looks low. The metric answer
    /// overshoots because real app names carry capitals and ascenders that pull the
    /// perceived middle back up, and the pixel answer overfits the one word it was
    /// measured on — so this takes the low end, which is the one that cannot look
    /// wrong in the other direction.
    static let opticalNudge: CGFloat = 0.5

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: size, height: size)
            .help("Running now")
            .accessibilityLabel("Running")
    }
}

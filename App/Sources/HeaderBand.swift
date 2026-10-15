import CoreGraphics

/// The padding a long-scroll changelog's list keeps above and below a version
/// header's own view (`ChangelogEntriesView.NotesScroll.bandInset`), read off
/// frames in the window. CoreGraphics only, so the app tests can reach it.
enum HeaderBand {
    /// The padding, from `header` and its section's first row (nil while not
    /// built), where the frames say it unambiguously; nil elsewhere.
    ///
    /// Floating, the header's offset from the list's top is the padding above
    /// it. In place, the gap between it and its first row is the padding below
    /// it, and the offset is that plus how far down the section sits. Floating
    /// with its first row under it, or in place below the top: from the two
    /// frames alone the same picture, so the offset counts only where it
    /// cannot be the second. The first row not built, or above the header's
    /// bottom: floating. Both readings equal: the header at the top, where
    /// either is the padding.
    static func padding(header: CGRect, firstRow: CGRect?, listTop: CGFloat) -> CGFloat? {
        let above = header.minY - listTop
        if let firstRow {
            let below = firstRow.minY - header.maxY
            if below >= 0, abs(above - below) > 0.5 { return nil }
        }
        guard above >= 0, above < header.height else { return nil }
        return above
    }
}

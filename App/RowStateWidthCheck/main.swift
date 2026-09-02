import AppKit
import Foundation

/// Measures the natural width of every translatable string the two row-action
/// views (`PopoverRowAction`, `WorkbenchRowAction`) actually draw, in each of a
/// small set of languages, against the same 320pt box every committed
/// `verify/row-states/*.png` tile is drawn into.
///
/// Why this exists (#263): `make gallery` pins English on purpose — `ImageRenderer`
/// follows the host language, so any other locale rewrites all 80 committed PNGs
/// with a diff that says nothing about the change under review (see that script's
/// own doc comment). The cost is that the sheet cannot see a translated string
/// overflowing its slot, which is the one failure this area has actually shipped
/// (`CLAUDE.md`: the status line left 9pt in Spanish; the workbench's first version
/// dropped `.lineLimit(1)`/`.minimumScaleFactor(0.7)` and Russian
/// "Ограничение частоты запросов" would have pushed the app name out).
///
/// Why this reads `Localizable.xcstrings` directly instead of rendering the real
/// views in a pinned locale
/// ------------------------------------------------------------------------------
/// The first version of this tool did what `RowStateGallery` does — build
/// `PopoverRowAction`/`WorkbenchRowAction` from `RowStateGalleryCases.all` and
/// render them via `ImageRenderer`, switching `AppleLanguages`/`AppleLocale` per
/// run. It does not work: a `type: tool` product (a bare Mach-O, not an `.app`
/// bundle) never gets `Localizable.xcstrings` compiled into it — confirmed by
/// building it with an explicit `Resources` phase and `GENERATE_INFOPLIST_FILE:
/// YES` and finding no `CompileXCStrings`/`.lproj` step anywhere in the build log,
/// and separately by a self-check inside the tool (comparing
/// `Bundle.main.preferredLocalizations.first` against the language it asked for)
/// that caught its own strings resolving to English regardless of
/// `AppleLanguages`. So `String(localized:)` in `PopoverRowAction`/
/// `RowActionViews.swift` always returns the English text in this kind of target,
/// no matter what locale the process is launched with — the SwiftUI-rendering
/// approach was measuring English in every language and would never have gone red.
///
/// This tool instead reads the actual translated VALUES out of
/// `App/Resources/Localizable.xcstrings` — the same file that ships to users — and
/// measures them with the real font/control each call site uses (`NSAttributedString`
/// for a `Text` tag, a real `NSButton` at the call site's `controlSize` for a
/// button), the same technique `MenuContentView.swift`'s own `nameColumnDemand`/
/// `showsStageLabel` already use for layout decisions, and the one PR #267's width
/// harness used for exactly this kind of question. No `AppleLanguages` pinning, no
/// process relaunch per language, no dependency on `DuoUpdaterCore` or SwiftUI.
///
/// What a pass proves, precisely
/// ------------------------------
/// This measures NATURAL (unconstrained) width — a string's width in its font with
/// no line limit applied — compared against `tileWidth`, NOT a simulation of
/// either window's real layout. `PopoverRowAction`'s real neighbour, in
/// `MenuContentView`, is a `minWidth` reservation (`trailingSlot`) that CONCEDES
/// width to a wide button rather than clipping it; `WorkbenchRowAction`'s only
/// production home (`WorkbenchWindowView.DetailHeader`) sits after a `Spacer()`
/// with roughly 900pt of window behind it. Nothing in this codebase hard-clips at
/// `tileWidth` today. What DOES hold: every tile in the committed English sheet
/// was drawn at exactly this width, so it is the widest any state's content has
/// ever actually been reviewed at — a string that needs MORE than that in another
/// language is asking for room no screenshot in this repo has shown to a human.
/// A pass is not a promise that nothing can ever look cramped in production; it is
/// a promise that this string, in this language, is not asking for more room than
/// the English baseline the sheet already treats as normal — the previously
/// invisible half of the failure class this exists to surface.
///
/// The report also prints each string's growth versus its English width, even
/// when it stays under budget: informational, not a second gate — there is no
/// non-arbitrary "acceptable growth" number to enforce, but the magnitude is worth
/// a human's eyes (Russian `Rate-limited` is +103pt over English at `.caption2`
/// while still clearing a 320pt budget by a wide margin, which is exactly the kind
/// of number a reviewer should see even though nothing here fails on it).
@MainActor
func run() -> Bool {
    let languages = Array(CommandLine.arguments.dropFirst())
    guard !languages.isEmpty else {
        print("usage: RowStateWidthCheck <language-code> [<language-code> ...]")
        return false
    }

    guard let catalog = loadCatalog() else {
        print("could not read/parse Resources/Localizable.xcstrings from the current"
              + " directory — run this from the repo root (row-state-width-check.sh does).")
        return false
    }

    let outDir = URL(fileURLWithPath: "verify/row-state-widths", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    // English widths per (key, kind), computed once so the report's "growth vs
    // English" column doesn't re-measure English on every language's pass.
    var englishWidths: [String: [String: CGFloat]] = [:]
    for entry in MeasuredString.all {
        var byKind: [String: CGFloat] = [:]
        for occurrence in entry.occurrences {
            byKind[occurrence.kind.reportKey] = occurrence.kind.width(of: entry.english)
        }
        englishWidths[entry.key] = byKind
    }

    var overallFailed = false
    for lang in languages {
        var lines: [String] = []
        var overflow: [String] = []
        var missing: [String] = []

        for entry in MeasuredString.all {
            let english = entry.english
            let value: String
            if lang == "en" {
                value = english
            } else if let translated = catalog.value(forKey: entry.key, language: lang) {
                value = translated
            } else {
                missing.append("\(entry.key) [\(lang)]")
                value = english
            }
            let englishWidthByKind = englishWidths[entry.key] ?? [:]
            for occurrence in entry.occurrences {
                let width = occurrence.kind.width(of: value)
                let budget = tileWidth
                let isOver = width > budget
                let baseline = englishWidthByKind[occurrence.kind.reportKey] ?? width
                let delta = width - baseline
                lines.append(
                    "\(occurrence.surface)/\(entry.key) [\(occurrence.kind.reportKey)]"
                    + "\t\(fmt(width))\t\(fmt(budget))\t\(isOver ? "OVERFLOW" : "ok")"
                    + "\t\(String(format: "%+.1f", delta))")
                if isOver {
                    overflow.append("\(occurrence.surface)/\(entry.key) [\(occurrence.kind.reportKey)]"
                                     + " = \"\(value)\" (\(fmt(width))pt > \(fmt(budget))pt)")
                }
            }
        }

        let header = "tile\twidth_pt\tbudget_pt\tstatus\tdelta_vs_en_pt\n"
        let report = header + lines.sorted().joined(separator: "\n") + "\n"
        let reportURL = outDir.appendingPathComponent("\(lang).txt")
        do {
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
        } catch {
            print("FAILED TO WRITE \(reportURL.path): \(error.localizedDescription)")
            overallFailed = true
            continue
        }

        print("\(lang): measured \(lines.count) strings → \(reportURL.path)")
        if !missing.isEmpty {
            print("\(lang): NO TRANSLATION FOUND (measured English as a stand-in,"
                  + " but this means catalogue coverage regressed): \(missing.joined(separator: ", "))")
            overallFailed = true
        }
        if overflow.isEmpty {
            print("\(lang): no string exceeds the \(fmt(tileWidth))pt tile width")
        } else {
            print("\(lang): OVERFLOW — \(overflow.count) string(s) exceed the tile width:")
            for o in overflow.sorted() { print("  \(o)") }
            overallFailed = true
        }
    }
    return !overallFailed
}

private func fmt(_ v: CGFloat) -> String { String(format: "%.1f", v) }

/// Mirrors `RowStateGalleryCases.tileWidth` (`App/RowStateGallery/Cases.swift`) —
/// the box every committed `verify/row-states/*.png` tile is drawn into.
/// Duplicated rather than imported: this tool does not build against
/// `DuoUpdaterCore`/SwiftUI at all (see the file header for why) — there is no
/// shared module to pull the constant from. Keep the two numbers in sync if
/// `tileWidth` there ever changes.
let tileWidth: CGFloat = 320

// MARK: - What gets measured, and how

/// One way a translated string is actually drawn — which surface, and with what
/// font/control (the exact modifiers read off `PopoverRowAction.swift`/
/// `RowActionViews.swift` at the time this was written).
struct Occurrence {
    let surface: String
    let kind: Kind
}

enum Kind {
    /// A plain `Text`, no line limit applied for this measurement (this tool
    /// measures NATURAL width — see the file header for what that does and
    /// doesn't prove about `.lineLimit(1)`/`.minimumScaleFactor(0.7)`, which both
    /// views apply to most of these).
    case tag(NSFont.TextStyle)
    /// A `Label`'s text portion — the icon and its spacing are fixed-width and
    /// not translation-dependent, so they are not measured; the doc comment on
    /// the caller explains why the two workbench-only badges without a popover
    /// counterpart are still measured this way rather than skipped.
    case label(NSFont.TextStyle)
    /// A real `NSButton`, at the same `controlSize` the call site uses — mirrors
    /// the technique memory `duo-updater-status-line-slot-width` already used and
    /// validated ("按钮用真 NSButton(.small) 量本地化标题") rather than
    /// approximating a button's chrome with `NSAttributedString`.
    case button(NSControl.ControlSize)

    /// A stable string for grouping/reporting — not shown to users, just makes
    /// the report and the delta-vs-English lookup key deterministic and readable
    /// (`NSFont.TextStyle.rawValue` is e.g. "UICTFontTextStyleCallout";
    /// `NSControl.ControlSize.rawValue` is a bare `Int`).
    var reportKey: String {
        switch self {
        case .tag(let style): return "tag:\(Self.shortName(style))"
        case .label(let style): return "label:\(Self.shortName(style))"
        case .button(let size): return "button:\(Self.shortName(size))"
        }
    }

    private static func shortName(_ style: NSFont.TextStyle) -> String {
        switch style {
        case .caption2: return "caption2"
        case .callout: return "callout"
        default: return style.rawValue
        }
    }

    private static func shortName(_ size: NSControl.ControlSize) -> String {
        switch size {
        case .mini: return "mini"
        case .small: return "small"
        case .regular: return "regular"
        case .large: return "large"
        @unknown default: return "size\(size.rawValue)"
        }
    }

    @MainActor
    func width(of value: String) -> CGFloat {
        switch self {
        case .tag(let style), .label(let style):
            let font = NSFont.preferredFont(forTextStyle: style)
            return NSAttributedString(string: value, attributes: [.font: font]).size().width
        case .button(let size):
            let button = NSButton(title: value, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = size
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: size))
            button.sizeToFit()
            return button.fittingSize.width
        }
    }
}

struct MeasuredString {
    /// The `Localizable.xcstrings` key.
    let key: String
    /// What English actually displays — equal to `key` for a plain
    /// `Text("...")`/`Button("...")` call site (no `defaultValue:`); different for
    /// `ignoredRowLabel()`/`skippedRowLabel()`, whose catalogue key
    /// ("Ignored (row status)"/"Skipped (row status)") is NOT what English shows
    /// (see `RowActionViews.swift`'s doc comment on those two functions) — and
    /// `Localizable.xcstrings` has no "en" entry for either (English is supplied
    /// entirely by the call site's `defaultValue:`, never written to the
    /// catalogue), so it cannot be read back the way every other key's English
    /// value can.
    let english: String
    let occurrences: [Occurrence]
}

extension MeasuredString {
    /// Every STATIC (non-interpolated) translatable string actually drawn inside
    /// `PopoverRowAction`'s and `WorkbenchRowAction`'s row bodies — read off
    /// `App/Sources/PopoverRowAction.swift` and `App/Sources/RowActionViews.swift`
    /// directly, 2026-09-02. Written out by hand rather than derived from the
    /// source, same as `RowStateGalleryCases.all` (see that file's own doc
    /// comment): deriving it would auto-cover a new string the moment it's added,
    /// which is exactly the "nobody drew it" gap that list exists to make
    /// noticeable. A new `Text`/`Button`/`Label` literal in either file needs a
    /// line added here.
    ///
    /// Excluded on purpose: the three explanation popovers' body text
    /// (`majorUpgradePopover`/`regionHintPopover`/`macCompatHintPopover`) — each
    /// wraps inside its own `.frame(width: 290)`/`.frame(width: 300)` with no
    /// `lineLimit`, so a long translation grows the panel TALLER, not wider; a
    /// height question, not the one this tool asks. Also excluded: strings built
    /// from interpolation whose English form isn't a single stable catalogue
    /// value (`"Update \(version)"`, the two App Store deep-link help strings,
    /// the restart/relaunch help texts) — `.help()` text is a separate, unmeasured
    /// gap named in the PR body, not folded in here to avoid conflating "this
    /// button's visible width" with "this tooltip might also be long".
    static let all: [MeasuredString] = [
        // MARK: Tags shared by both surfaces (popover .caption2, workbench .callout)
        MeasuredString(key: "Ignored (row status)", english: "Ignored", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Skipped (row status)", english: "Skipped", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Failed", english: "Failed", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Rate-limited", english: "Rate-limited", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "App Store", english: "App Store", occurrences: [
            // `sourceHint(for:)`'s tag, AND the button both surfaces show for an
            // App Store row that isn't managed here / isn't gated.
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .tag(.callout)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Sparkle", english: "Sparkle", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "TestFlight", english: "TestFlight", occurrences: [
            // Both the managed-tag (`testFlightManagedLabel`/`testFlightManagedTile`)
            // and the button (`testFlightButton`/the workbench's TestFlight route).
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .tag(.callout)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Relaunching…", english: "Relaunching…", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Updated", english: "Updated", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        // installStageLabel's static values (the dynamic "N%" case is digits, not
        // translated text — excluded).
        MeasuredString(key: "Queued", english: "Queued", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Checking", english: "Checking", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Verifying", english: "Verifying", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Extracting", english: "Extracting", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Installing", english: "Installing", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),
        MeasuredString(key: "Installed", english: "Installed", occurrences: [
            .init(surface: "popover", kind: .tag(.caption2)),
            .init(surface: "workbench", kind: .tag(.callout)),
        ]),

        // MARK: Buttons — popover is always .controlSize(.small); workbench never
        // sets a controlSize, i.e. the default (.regular).
        MeasuredString(key: "Update", english: "Update", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Install", english: "Install", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Relaunch", english: "Relaunch", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Relaunch now", english: "Relaunch now", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Toolbox", english: "Toolbox", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Open", english: "Open", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        MeasuredString(key: "Reveal in Finder", english: "Reveal in Finder", occurrences: [
            .init(surface: "popover", kind: .button(.small)),
            .init(surface: "workbench", kind: .button(.regular)),
        ]),
        // Workbench-only: `DetectionOnlyAffordance` gives the popover just "Open"
        // for `.openPage` (already covered above); the workbench titles that same
        // case "Open page" instead (`RowActionViews.swift`'s own comment: "this
        // host's own call, kept out of the shared type on purpose").
        MeasuredString(key: "Open page", english: "Open page", occurrences: [
            .init(surface: "workbench", kind: .button(.regular)),
        ]),

        // MARK: Workbench-only Label badges (major upgrade / App Store gates).
        // The popover draws the equivalent state as a bare SF Symbol badge with no
        // text at all (`majorUpgradeBadge`/`appStoreTrailing`'s gate branches) — so
        // there is no popover occurrence to pair these with, unlike everything
        // above.
        MeasuredString(key: "Major update", english: "Major update", occurrences: [
            .init(surface: "workbench", kind: .label(.callout)),
        ]),
        MeasuredString(key: "Not supported on this Mac", english: "Not supported on this Mac", occurrences: [
            .init(surface: "workbench", kind: .label(.callout)),
        ]),
        MeasuredString(key: "Region-locked", english: "Region-locked", occurrences: [
            .init(surface: "workbench", kind: .label(.callout)),
        ]),
    ]
}

// MARK: - Reading Localizable.xcstrings directly

struct StringCatalog {
    /// key -> language -> translated value
    let values: [String: [String: String]]

    func value(forKey key: String, language: String) -> String? {
        values[key]?[language]
    }
}

private func loadCatalog() -> StringCatalog? {
    let url = URL(fileURLWithPath: "App/Resources/Localizable.xcstrings")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any] else {
        return nil
    }
    var values: [String: [String: String]] = [:]
    for (key, entryAny) in strings {
        guard let entry = entryAny as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any] else { continue }
        var byLang: [String: String] = [:]
        for (lang, locAny) in localizations {
            guard let loc = locAny as? [String: Any],
                  let unit = loc["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String else { continue }
            byLang[lang] = value
        }
        values[key] = byLang
    }
    return StringCatalog(values: values)
}

// Same reasoning as `RowStateGallery/main.swift`: a `tool` target's top level is
// not implicitly main-actor bound.
MainActor.assumeIsolated {
    if !run() { exit(1) }
}

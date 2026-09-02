import AppKit
import SwiftUI
import DuoUpdaterCore

/// Renders every `RowActionState` to a reference PNG, so a change to how a state
/// is drawn shows up as an image diff instead of being noticed in use — or not.
///
/// This exists because the two windows' row rendering has no other executable
/// check. `App/project.yml` has no test target, so nothing runs `App/Sources`; the
/// Core tests cover which state a row IS (`RowActionStateTests`) but not what that
/// state looks like, and the failure mode that motivated all of this was a state
/// rendering as *nothing at all* — invisible to any assertion about the state
/// itself.
///
/// Run it with `make gallery`. Output goes to `verify/row-states/`, which is
/// committed: regenerate after a UI change and read the diff.
@MainActor
func render() {
    let outDir = URL(fileURLWithPath: "verify/row-states", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    var written: [String] = []
    var unrendered: [String] = []
    var blank: [String] = []
    // Every surface-qualified name that actually rendered blank this run, exempted
    // or not — the audit below needs the full set, not just the violations `blank`
    // collects, to tell a live exemption from a dead one (#271).
    var actuallyBlank: Set<String> = []
    // Tiles that contain ImageRenderer's placeholder signature (#269) but are not
    // in `notFaithful` — a silent lie the sheet was previously making no assertion
    // about at all.
    var unregisteredPlaceholder: [String] = []
    /// surface → rendered bytes → EVERY state that drew them. All of them, not
    /// just the first: comparing a new tile against a single predecessor makes the
    /// outcome depend on the order the cases happen to be listed in, and this list
    /// gets renumbered. With three states sharing a picture and two of the three
    /// pairs exempt, keeping only one predecessor lets the third pair go unreported.
    var drawn: [String: [String: [String]]] = [:]
    var identical: [String] = []
    // Both surfaces, from the same state. Rendering them side by side is the point:
    // a state that reads differently in the two windows shows up as two tiles that
    // disagree, which is the class of bug that made this necessary.
    for (surface, tile) in RowStateGalleryCases.surfaces {
    for (name, state, result) in RowStateGalleryCases.all {
        // Sizing now lives inside `tile` itself (see `popoverTile`/`workbenchTile`):
        // every ordinary row still gets the 320×44 slot, but the three
        // explanation-content cases size to their own content instead of being
        // forced into a row-sized box that would clip a paragraph.
        let view = tile(name, state, result)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // NOT just a stderr line. The output directory is wiped before every
            // run, so a tile that does not render leaves no file at all — which is
            // "a state nobody drew", the one thing this tool exists to refuse. It
            // used to `continue` and let the run exit 0.
            unrendered.append("\(surface)/\(name)")
            continue
        }
        // A state that draws nothing is the bug this whole gallery is for, so it is
        // reported rather than silently written as an empty tile.
        let isBlank = RowStateGalleryCases.isBlank(rep)
        if isBlank {
            actuallyBlank.insert("\(surface)/\(name)")
            if !RowStateGalleryCases.mayBeBlank.contains("\(surface)/\(name)") {
                blank.append("\(surface)/\(name)")
            }
        }
        // A tile carrying ImageRenderer's placeholder is drawn, so the blank gate
        // above has nothing to say about it — this is the check that does (#269).
        let placeholderCount = RowStateGalleryCases.placeholderPixelCount(rep)
        if placeholderCount > RowStateGalleryCases.placeholderPixelThreshold,
           !RowStateGalleryCases.notFaithful.contains("\(surface)/\(name)") {
            unregisteredPlaceholder.append("\(surface)/\(name) (\(placeholderCount)px)")
        }
        // Two states that draw the SAME pixels on one surface means the view is not
        // reading something the state carries. That is how the popover kept its own
        // `stagedFileName` / `storeManagedHere` / `result.status` after the ladder
        // moved to Core: the tiles came out byte-identical and nothing complained,
        // because the blank check only asks whether SOMETHING was drawn. States
        // whose pictures are legitimately identical (only the tooltip differs) are
        // listed in `mayLookAlike`.
        // Blank tiles collide with every other blank tile by construction, so the
        // collision gate has nothing to say about them — the blank gate above is the
        // one that judges those.
        let digest = png.base64EncodedString()
        for twin in isBlank ? [] : drawn[surface]?[digest] ?? []
        where !RowStateGalleryCases.mayLookAlike
            .contains(["\(surface)/\(twin)", "\(surface)/\(name)"]) {
            identical.append("\(surface)/\(twin) == \(surface)/\(name)")
        }
        drawn[surface, default: [:]][digest, default: []].append(name)
        let surfaceDir = outDir.appendingPathComponent(surface, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: surfaceDir, withIntermediateDirectories: true)
            try png.write(to: surfaceDir.appendingPathComponent("\(name).png"))
            written.append("\(surface)/\(name)")
        } catch {
            // Same reasoning as the render failure: a discarded write is a missing
            // committed tile. It was `try?`, and `written` was incremented anyway,
            // so the run could report 68 tiles with 67 on disk.
            unrendered.append("\(surface)/\(name) (\(error.localizedDescription))")
        }
    }
    }

    print("rendered \(written.count) states → \(outDir.path)")
    // Named every run rather than left in a comment: a picture that lies is worse
    // than no picture, and the only defence is that nobody opens these three
    // expecting the truth. Two ImageRenderer gaps land here: an SF Symbol inside a
    // `.buttonStyle(.borderless)` button (workbench draws the same state
    // correctly, via `Label` — read that tile instead), and, found while adding
    // #265's cases, a plain `ProgressView()` (no such alternate — see
    // `notFaithful`'s doc comment for which is which).
    print("NOT FAITHFUL (see RowStateGalleryCases.notFaithful for why each one): "
          + RowStateGalleryCases.notFaithful.sorted().joined(separator: ", "))
    var failed = false
    // #265: the gallery images alone are a diff, not an assertion — this pins
    // `DownloadReadout`'s widest-first declaration order directly, independent of
    // which tiles get rendered.
    if RowStateGalleryCases.downloadReadoutOrderIsIntact() {
        print("DownloadReadout order intact (barAndPercent, ringAndPercent, ringOnly)")
    } else {
        print("DOWNLOAD READOUT ORDER CHANGED: `DownloadReadout` must stay widest-first"
              + " (barAndPercent, ringAndPercent, ringOnly) — AppRow walks `allCases`"
              + " and takes the first that fits, so this order IS the algorithm."
              + " Reordering it silently changes which readout every downloading row"
              + " gets, with no compile error and no other test to catch it.")
        failed = true
    }
    if !unrendered.isEmpty {
        print("NOT WRITTEN (no tile on disk for these states): "
              + unrendered.joined(separator: ", "))
        failed = true
    }
    // An exemption that no longer matches anything is a standing permission for a
    // divergence to reappear unreported, and the list is maintained by hand. Making
    // the tightening of a view fail the build is the point: whoever made the two
    // tiles differ is the person who should retire the exemption.
    let drawnPairs = Set(drawn.flatMap { surface, byDigest in
        byDigest.values.flatMap { names in
            names.flatMap { a in names.map { b in Set(["\(surface)/\(a)", "\(surface)/\(b)"]) } }
        }
    }.filter { $0.count == 2 })
    let deadExemptions = RowStateGalleryCases.mayLookAlike.subtracting(drawnPairs)
    if !deadExemptions.isEmpty {
        print("DEAD EXEMPTION (these no longer draw alike — drop them from"
              + " mayLookAlike): "
              + deadExemptions.map { $0.sorted().joined(separator: " == ") }
                  .sorted().joined(separator: ", "))
        failed = true
    }
    // Same reasoning, same shape, applied to the OTHER hand-maintained exemption
    // list: `mayBeBlank` used to be consulted but never audited, so an entry that
    // stopped drawing blank stayed exempt forever instead of the detector picking
    // it back up (#271 — #260 walked into exactly this with `workbench/31`/`/32`
    // and only caught it because someone happened to remove the entries by hand).
    let deadBlankExemptions = RowStateGalleryCases.mayBeBlank.subtracting(actuallyBlank)
    if !deadBlankExemptions.isEmpty {
        print("DEAD EXEMPTION (these no longer render blank — drop them from"
              + " mayBeBlank): "
              + deadBlankExemptions.sorted().joined(separator: ", "))
        failed = true
    }
    if blank.isEmpty {
        print("no state renders blank")
    } else {
        print("BLANK (a state drawing nothing): \(blank.joined(separator: ", "))")
        failed = true
    }
    // #269: a placeholder-bearing tile used to be indistinguishable from a
    // genuine one — nothing scanned pixels, so `notFaithful` only grew when a
    // human happened to notice. This makes an unregistered placeholder a build
    // failure instead of a silent lie in the committed sheet.
    if unregisteredPlaceholder.isEmpty {
        print("no unregistered ImageRenderer placeholder pixels")
    } else {
        print("UNFAITHFUL TILE NOT REGISTERED (contains ImageRenderer's placeholder"
              + " signature — see RowStateGalleryCases.placeholderPixelCount — but is"
              + " missing from notFaithful; register it there with a reason, don't"
              + " just silence this): " + unregisteredPlaceholder.joined(separator: ", "))
        failed = true
    }
    if identical.isEmpty {
        print("no two states draw the same tile")
    } else {
        print("IDENTICAL (a view is ignoring something the state carries, or the two"
              + " really do look alike — then list the pair in mayLookAlike): "
              + identical.joined(separator: ", "))
        failed = true
    }

    // #263: TWO of `mayLookAlike`'s seven pairs are justified in their own comment
    // as differentiated BY the tooltip ("the help text says which one" for
    // 10-vs-11, "the tooltip is what separates them" for 13-vs-19) — a claim
    // nothing checked, because `.help()` text is invisible in a PNG by
    // construction. This verifies those two rather than trusting them: collect
    // every `.help()` string reachable from each side (via `collectHelpTexts`'s
    // Mirror-reflection walk — see its own doc comment for the technique and its
    // risk) and require the two sets to differ.
    //
    // Deliberately NOT applied to the other five pairs (15-vs-28, 18-vs-22,
    // 17-vs-23, 27-vs-31, 29-vs-32): their own comments claim the OPPOSITE —
    // "one button", "a tile cannot show which explanation appears", "the same
    // marker … never reads like something we could update ourselves" — i.e. those
    // are deliberately identical end-to-end, tooltip included, not "differentiated
    // by a tooltip nothing here checks". Running this check against them found
    // exactly that (identical tooltips) on a first pass — a real discovery, but not
    // a bug: verified against `RowActionViews.swift`, all three ARE the same
    // control/wording by design. Folding them into `tooltipDifferentiatedPairs`
    // would have turned a correct design decision into a build failure.
    switch tooltipsDifferentiateExemptedPairs() {
    case .ok(let checked):
        print("\(checked) mayLookAlike pair(s) claiming a tooltip differentiator"
              + " checked — every one actually has a different tooltip on each side")
    case .undifferentiated(let names):
        print("TOOLTIP DOES NOT DIFFERENTIATE (pixels match AND every collected"
              + " .help() string matches too — the exemption's own justification is"
              + " false): " + names.joined(separator: ", "))
        failed = true
    case .extractorBroken:
        // Distinguished from `.undifferentiated` on purpose: if Mirror found NO
        // `.help()` text anywhere in the whole run, that is far more likely
        // SwiftUI's private internal shape having changed out from under
        // `collectHelpTexts` (undocumented by Apple, not guaranteed stable across
        // an OS/Xcode update) than every single row in the app suddenly losing
        // its tooltips. Reporting it as its own failure, rather than as N
        // `.undifferentiated` pairs, keeps a real extractor break from reading
        // like a wall of unrelated view regressions.
        print("TOOLTIP EXTRACTOR FOUND NOTHING ANYWHERE: either every `.help()` in"
              + " the app was removed, or collectHelpTexts's Mirror-reflection"
              + " technique no longer matches this SwiftUI version's private"
              + " HelpView<Content> shape — see that function's doc comment.")
        failed = true
    case .driftedFromMayLookAlike:
        print("TOOLTIP CHECK SCOPE DRIFTED: tooltipDifferentiatedPairs names a pair"
              + " that is no longer in RowStateGalleryCases.mayLookAlike — update"
              + " (or remove) it to match.")
        failed = true
    }

    if failed { exit(1) }
}

/// Result of checking every `mayLookAlike` pair's tooltip text against its pixel
/// exemption. `.extractorBroken` is kept distinct from `.undifferentiated([...])`
/// — see the call site for why that distinction matters.
enum TooltipCheckResult {
    case ok(checked: Int)
    case undifferentiated([String])
    case extractorBroken
    case driftedFromMayLookAlike
}

/// `.body` for `PopoverRowAction`/`WorkbenchRowAction` at a state's DEFAULT
/// `downloadReadout`/`showsStageLabel` — the same defaults `popoverTile`'s
/// non-explanation branch uses. Deliberately NOT `RowStateGalleryCases`'
/// `popoverTile`/`workbenchTile`: those wrap the constructed view in `.frame(...)`
/// and `AnyView` for the PNG pass, and `Mirror` only sees a view's STORED
/// properties — it cannot see through an unevaluated `body` computed property, so
/// reflecting the wrapped-but-unevaluated struct finds nothing at all (confirmed:
/// an earlier version of this function did exactly that and always reported
/// `.extractorBroken`). Calling `.body` explicitly, on the concrete type, forces
/// SwiftUI to evaluate the `switch state { … }` into its actual primitive tree
/// (`Button`, `HelpView`, `_ConditionalContent`, …) BEFORE `Mirror` ever sees it —
/// which is also why this can't be generalized to walk an arbitrary `AnyView`:
/// it relies on knowing the concrete type at the call site.
@MainActor
private func rowActionHelpTexts(surface: String, state: RowActionState, result: UpdateResult) -> [String] {
    switch surface {
    case "popover": return collectHelpTexts(PopoverRowAction(state: state, result: result).body)
    case "workbench": return collectHelpTexts(WorkbenchRowAction(state: state, result: result).body)
    default: return []
    }
}

/// The subset of `RowStateGalleryCases.mayLookAlike` whose OWN comment claims a
/// tooltip differentiates the pair — copied out by name rather than computed from
/// the comment text (comments aren't data). The other five pairs there claim the
/// opposite (deliberately identical end-to-end — see the doc comment on this
/// function's call site for why folding them in would be wrong), so this list is
/// intentionally shorter than `mayLookAlike` itself, not a stand-in for it.
private let tooltipDifferentiatedPairs: Set<Set<String>> = [
    // "Both an orange bordered Relaunch; the help text says which one."
    ["popover/10-relaunch-to-apply-staged", "popover/11-restart-to-apply"],
    ["workbench/10-relaunch-to-apply-staged", "workbench/11-restart-to-apply"],
    // "Both a bordered Update: … the tooltip is what separates them."
    ["popover/13-update-installer", "popover/19-update-app-store"],
    ["workbench/13-update-installer", "workbench/19-update-app-store"],
]

@MainActor
func tooltipsDifferentiateExemptedPairs() -> TooltipCheckResult {
    // `tooltipDifferentiatedPairs` is a hand-copied subset of `mayLookAlike` — if
    // a pair is ever dropped or renamed there without this list following, the
    // loop below would silently skip it (the per-pair `guard` just `continue`s on
    // a lookup miss) rather than flag the drift. Since a `Set` of `Set<String>`
    // has no ordering to make "sorted().joined" complain about, catching this
    // takes an explicit subset check.
    guard tooltipDifferentiatedPairs.isSubset(of: RowStateGalleryCases.mayLookAlike) else {
        return .driftedFromMayLookAlike
    }

    let byName = Dictionary(uniqueKeysWithValues: RowStateGalleryCases.all.map { ($0.0, $0) })
    var totalHelpStringsFound = 0
    var undifferentiated: [String] = []
    var checked = 0

    for pair in tooltipDifferentiatedPairs {
        let members = pair.sorted()
        guard members.count == 2,
              let slashA = members[0].firstIndex(of: "/"),
              let slashB = members[1].firstIndex(of: "/") else { continue }
        let surfaceA = String(members[0][..<slashA]), nameA = String(members[0][members[0].index(after: slashA)...])
        let surfaceB = String(members[1][..<slashB]), nameB = String(members[1][members[1].index(after: slashB)...])
        // The three explanation-content names (38–40) aren't in `RowStateGalleryCases
        // .all`'s SURFACE-neutral form the way this lookup wants — they're not part
        // of any `mayLookAlike` pair today, so this is a defensive guard, not a
        // known gap.
        guard surfaceA == surfaceB,
              let (_, stateA, resultA) = byName[nameA],
              let (_, stateB, resultB) = byName[nameB] else { continue }

        let helpA = Set(rowActionHelpTexts(surface: surfaceA, state: stateA, result: resultA))
        let helpB = Set(rowActionHelpTexts(surface: surfaceA, state: stateB, result: resultB))
        totalHelpStringsFound += helpA.count + helpB.count
        checked += 1
        if helpA == helpB {
            undifferentiated.append("\(surfaceA): \(nameA) vs \(nameB)"
                                     + " (tooltip set: \(helpA.sorted()))")
        }
    }

    guard totalHelpStringsFound > 0 else { return .extractorBroken }
    guard undifferentiated.isEmpty else { return .undifferentiated(undifferentiated.sorted()) }
    return .ok(checked: checked)
}

/// Recursively finds every `.help(...)` payload in a rendered view's tree via
/// `Mirror` reflection. SwiftUI wraps a `.help()` call in a private `HelpView
/// <Content>` type carrying the wrapped content plus the help text as a `Text`;
/// walking for a node whose runtime type name starts with `"HelpView<"` and
/// pulling every `String` leaf out of its `text` child recovers the tooltip
/// content with no accessibility tree, no window, and no on-screen anchor —
/// unlike every other AX-driving technique this repo has needed (see memory
/// `duo-updater-ax-popover-driving`), because this walks a view VALUE this
/// process itself constructed, not another process's rendered window.
///
/// Verified against SwiftUI's current (2026-09, Xcode 27 beta) internal shape for
/// both patterns `PopoverRowAction`/`WorkbenchRowAction` actually use: a literal
/// `.help("...")` (stored as a `LocalizedStringKey`) and `.help(someString)`
/// (stored as a verbatim `String`) — both landed inside the same `HelpView`
/// wrapper's `text` child, just with different internal storage underneath, which
/// is why this walks for ANY `String` leaf rather than one specific storage shape.
/// Also verified past an unrelated sibling `.help()` in the same `HStack`, and
/// (separately, in a throwaway probe — not exercised by this file's actual call
/// site, which never wraps in `AnyView`) confirmed to still work through `AnyView`
/// erasure.
///
/// Fragile BY CONSTRUCTION: `HelpView` and its internal layout are undocumented
/// SwiftUI implementation details, not a stable public contract, and Apple can
/// reshape them on any OS/Swift Toolchain update with no compiler error — this
/// would simply stop finding anything. `tooltipsDifferentiateExemptedPairs()`'s
/// `.extractorBroken` case is the guard against that turning into silent false
/// failures (or worse, a silent false pass) if it ever happens.
@MainActor
func collectHelpTexts(_ any: Any, depth: Int = 0) -> [String] {
    // A real view tree from this app is nowhere near this deep; the cutoff exists
    // so a future SwiftUI internal shape with a reference cycle in its Mirror
    // children (unlikely, but undocumented territory) fails closed with an empty
    // result — caught by `.extractorBroken` — rather than hanging.
    guard depth <= 60 else { return [] }
    let mirror = Mirror(reflecting: any)
    var found: [String] = []
    if String(describing: mirror.subjectType).hasPrefix("HelpView<") {
        for child in mirror.children where child.label == "text" {
            found.append(contentsOf: stringLeaves(child.value))
        }
    }
    for child in mirror.children {
        found.append(contentsOf: collectHelpTexts(child.value, depth: depth + 1))
    }
    return found
}

private func stringLeaves(_ any: Any, depth: Int = 0) -> [String] {
    guard depth <= 60 else { return [] }
    if let s = any as? String { return [s] }
    let mirror = Mirror(reflecting: any)
    var found: [String] = []
    for child in mirror.children {
        found.append(contentsOf: stringLeaves(child.value, depth: depth + 1))
    }
    return found
}

// `ImageRenderer` and AppKit are main-actor bound, and a `tool` target's top level
// is not — so hop explicitly rather than relying on the implicit main actor a
// SwiftUI app would have.
MainActor.assumeIsolated { render() }

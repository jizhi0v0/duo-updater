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
        if isBlank, !RowStateGalleryCases.mayBeBlank.contains("\(surface)/\(name)") {
            blank.append("\(surface)/\(name)")
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
    if blank.isEmpty {
        print("no state renders blank")
    } else {
        print("BLANK (a state drawing nothing): \(blank.joined(separator: ", "))")
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
    if failed { exit(1) }
}

// `ImageRenderer` and AppKit are main-actor bound, and a `tool` target's top level
// is not — so hop explicitly rather than relying on the implicit main actor a
// SwiftUI app would have.
MainActor.assumeIsolated { render() }

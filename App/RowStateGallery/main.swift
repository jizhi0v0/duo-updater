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

    var written = 0
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
        let view = tile(state, result)
            .frame(width: 320, height: 44, alignment: .trailing)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not render \(surface)/\(name)\n".utf8))
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
        try? FileManager.default.createDirectory(at: surfaceDir, withIntermediateDirectories: true)
        try? png.write(to: surfaceDir.appendingPathComponent("\(name).png"))
        written += 1
    }
    }

    print("rendered \(written) states → \(outDir.path)")
    // Named every run rather than left in a comment: a picture that lies is worse
    // than no picture, and the only defence is that nobody opens these three
    // expecting the truth.
    print("NOT FAITHFUL (ImageRenderer cannot draw an SF Symbol in a borderless"
          + " button — read the workbench tile for these states instead): "
          + RowStateGalleryCases.notFaithful.sorted().joined(separator: ", "))
    var failed = false
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

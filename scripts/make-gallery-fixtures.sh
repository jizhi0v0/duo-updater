#!/bin/bash
# Regenerate the committed fixture images `RowStateGallery` draws with.
#
# Only one so far: TestFlight's icon. The gallery must not read the machine's own
# copy — see `AppIconCache.testFlight` for why (a Mac without TestFlight renders
# the word instead of the icon, and every gallery gate stays green while four
# reference tiles flip). Snapshotting it here is the trade that buys that: the
# sheet stops depending on the host, at the cost of going stale if Apple
# redraws the icon. Re-run this when it does.
#
# Captured the way the row draws it — `NSWorkspace.icon(forFile:)`, 16pt at the
# gallery's `renderer.scale = 2` — rather than by pulling a rep out of
# AppIcon.icns, which on macOS 27 is a visibly different picture from what the
# app actually gets.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) && cd "$ROOT"

OUT="App/RowStateGallery/Fixtures/testflight-icon@2x.png"
mkdir -p "$(dirname "$OUT")"

swift - "$OUT" <<'SWIFT'
import AppKit

let out = CommandLine.arguments[1]
guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TestFlight") else {
    FileHandle.standardError.write(Data("TestFlight is not installed — cannot capture its icon.\n".utf8))
    exit(1)
}
let icon = NSWorkspace.shared.icon(forFile: app.path)
// 32x32 device pixels standing for a 16pt tag at scale 2, so the gallery draws
// the fixture 1:1 and nothing resamples it.
guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: 16, height: 16)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
SWIFT

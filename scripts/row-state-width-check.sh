#!/bin/bash
# Measure every translatable row-action string's natural width, in each of a
# small set of languages, against RowStateGalleryCases.tileWidth (320pt) — the
# box every committed verify/row-states/*.png tile is drawn into.
#
# Companion to `make gallery`, not a replacement for it: that script pins English
# on purpose (`ImageRenderer` follows the host language, so a run in any other
# locale rewrites all 80 committed PNGs with a diff that says nothing about the
# change under review — see its own comment). That pin is also why the sheet
# structurally cannot see the one failure this area has actually shipped: a
# translated string overflowing its slot (CLAUDE.md: the status line left 9pt in
# Spanish; the workbench once dropped .lineLimit(1)/.minimumScaleFactor(0.7) and
# Russian "Ограничение частоты запросов" would have pushed the app name out).
# Rather than double the committed image count (#263's option 1), this MEASURES —
# see App/RowStateWidthCheck/main.swift for exactly what a pass proves, and why
# it reads Localizable.xcstrings directly instead of rendering the real views in
# a pinned locale (that was tried first; it does not work for a `tool` product) —
# and commits the measurements, not a second set of pictures.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DD="${GALLERY_DD:-/tmp/duo-gallery}"

# Same reasoning as row-state-gallery.sh: must be exported before xcodegen, or a
# bare `xcodegen generate` writes an empty DEVELOPMENT_TEAM that only breaks the
# next `make install`.
TEAM="${DUO_TEAM_ID:-RS59HDH7Y3}"
export DUO_TEAM_ID="$TEAM"

cd "$REPO"
xcodegen generate --spec App/project.yml --project App >/dev/null

xcodebuild -project App/DuoUpdater.xcodeproj \
           -scheme RowStateWidthCheck -configuration Debug \
           -derivedDataPath "$DD" build >/dev/null

BIN="$DD/Build/Products/Debug/RowStateWidthCheck"

# Wipe first, same reasoning as the gallery: a retired language or a string no
# longer drawn must not leave a stale report behind for something that no longer
# runs.
rm -rf "$REPO/verify/row-state-widths"

# Which languages, and why these and not all six the catalogue ships (de, es, fr,
# ja, ru, zh-Hans): measured on 2026-09-02 against the real Localizable.xcstrings
# values for every row-action catalogue key (Update/Relaunch/Install/App
# Store/Toolbox/TestFlight/Ignored/Skipped/Rate-limited/Failed/Major
# update/Region-locked/Not supported on this Mac/Open page/Reveal in
# Finder/Queued/Extracting/Installing), at both fonts these views actually use
# (.caption2 popover, .callout workbench), via NSAttributedString — the same
# technique #267's width harness used, and the one MenuContentView.swift's own
# `nameColumnDemand`/`showsStageLabel` measurements use in production. Average
# width delta vs. English, at .callout:
#
#   ru +41.0pt (worst — and the single worst case: Rate-limited +119.3pt, the
#               exact string CLAUDE.md already names)
#   fr +25.5pt (second-worst average, narrowly ahead of de; its own
#               parenthetical already caused a real bug, fixed in #267)
#   de +24.5pt
#   es +16.1pt
#   ja  +6.7pt (net narrower on several keys — CJK glyphs are compact; a few
#               multi-kana words still run wide, e.g. Install +34.9pt)
#   zh-Hans -17.8pt (narrower than English on every measured key — no signal)
#
# ru and fr are the two that actually threaten this layout; de trails fr by only
# 1pt on average but neither de nor es tops ru or fr on ANY key measured. ja and
# zh-Hans would not exercise the failure mode at all — including all six would
# inflate the report for two languages that have never once been the wide one.
"$BIN" en ru fr

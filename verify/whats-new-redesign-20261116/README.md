# What's New window redesign

Validated on an Apple Silicon Mac running macOS 27.3 (26C5035r).

The PNGs are offscreen renders of the production SwiftUI history view, shared
note renderer and sidebar. A temporary native `NSHostingView` harness used the
published English / Simplified Chinese changelogs and GitHub publication dates.
These captures show window content, without native title-bar chrome.

- `dark.png` / `light.png`: 960 × 652 pt content.
- `minimum.png`: 720 × 480 pt content.
- `wide.png`: 1280 × 772 pt content; the reading column stays bounded.
- `chinese.png`: Simplified Chinese note content at 960 × 652 pt.

## Live-window result (2026-11-16)

A separate, running SwiftUI verification app hosted the production
`SelfChangelogHistoryView`, `ChangelogEntryView`, sidebar and supporting views
from this branch. Its Window used the shipping default size, minimum content
size and content-minimum resizability, with preloaded published notes/dates.
Cua-driver supplied AX/key/wheel input; DuoShot captured the actual window in
isolated mode. The canonical DuoUpdater installation was not replaced.

- Version rows expose combined version/date labels as AX buttons. AXPress on
  `0.5.24` changed the heading and Copy label to that version.
- Tab followed by Up returned to `0.5.25-beta.1`; Down/Up also switched between
  the first two releases after the accessibility fix.
- Page Down selected `0.5.21`; Page Up returned to `0.5.25-beta.1`.
- End selected the oldest entry, `0.1.9`; Home returned to the latest entry.
- Resizing to a 720 × 512 pt window (720 × 480 pt content) kept the full version
  labels and header controls readable.
- A wheel scroll moved the stable release's notes while the version/date/Copy
  header stayed fixed (`live-scrolled.png`). Selecting another release and
  returning to stable reset its notes to the opening paragraph (`live-reset.png`).
- Copy showed its checkmark feedback (`live-copy.png`), then returned to its copy
  glyph (`live-default.png`). The clipboard matched all 11 published stable
  paragraphs, 2,287 characters, exactly.

The initial AX read exposed release rows only as static text. Combining each
row's accessibility children and marking it as a button fixed AX activation;
all results above were rechecked with that fix in place. `live-results.json`
records version readbacks and the clipboard comparison; `live-actions.jsonl`
contains the underlying action/state responses.

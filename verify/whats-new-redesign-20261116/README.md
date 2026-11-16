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

Live-window interaction remains unverified: the native computer-control
connection returned an app-server error. Version clicks, keyboard navigation,
scrolling / scroll reset, and Copy feedback still need a real-window check.
Keep the PR's `needs-real-machine` hold until that evidence is recorded.

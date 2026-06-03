# PermissionFlow (vendored)

Source: https://github.com/jaywcjlove/PermissionFlow — MIT License (see `LICENSE`).

We vendor a **minimal subset** of the package's source instead of taking the SPM
dependency, because the upstream `Package.swift` declares
`swift-tools-version: 6.2`, which a 6.0/6.1 toolchain refuses to resolve. Vendoring
also keeps us on the project's "pure Swift, few dependencies" footing.

## What we kept
- `SystemSettings*.swift`, `SettingsNavigator.swift` — System Settings deep links.
- `PermissionFlow.swift`, `PermissionFlowController.swift`, `PermissionFlowPane.swift`,
  `PermissionFlowConfiguration.swift` — flow orchestration.
- `FloatingDropPanel.swift`, `AppDropArea.swift`, `PermissionFlowPanelView.swift` —
  the floating drag-to-authorize panel.
- `SettingsWindowTracker.swift` — tracks the System Settings window position.

## Local changes
- Collapsed the `SystemSettingsKit` module into this target (dropped
  `import SystemSettingsKit`); everything compiles as one module.
- `PermissionFlowLocalizer` stubbed to return the English `defaultValue` (we don't
  ship the upstream `.lproj` resource bundle, so `Bundle.module` is unavailable).
- Dropped the status-detection machinery (`PermissionStatusRegistry`, providers,
  `PermissionFlowButton*`) — unused; App Management has no status API anyway.
- `PermissionFlowController.showPanel()` now defers the floating drag card until
  `SettingsWindowTracker` reports the first real window frame (with a 2s fallback),
  instead of showing it immediately. Upstream shows the card the instant
  `authorize(...)` runs, which — because `SystemSettings.open(...)` is async — left
  the card floating over an empty screen before System Settings had opened and
  navigated to the pane.
- `PermissionFlowController` debounces the **first** tracked frame (~80ms of frame
  stability) before flying the card in, so the fly-in lands on a settled pane
  instead of chasing System Settings while it's still resizing onto the pane.
  Later frames still follow the window live.
- `FloatingDropPanel` launch animation rewritten for smoothness: the window holds
  its final size for the whole flight (only the origin moves; the content layer
  scales up via a `CATransform`), so the SwiftUI host no longer relayouts every
  frame. It's paced by a `CADisplayLink` (macOS 14+, `Timer` fallback) instead of a
  free-running `Timer`. Upstream resized the window each frame off a `Timer`, which
  dropped frames. The window shadow is suppressed mid-flight (the transparent
  margin around the scaled content would otherwise cast a full-size shadow box).
  The unused `show(at:)` / `launchSourceFrame(_:)` were dropped; the
  tracking-failure fallback now just centers the card at full size.

## Why we use it
Granting **App Management** (`kTCCServiceSystemPolicyAppBundles`) has no request
API. This drives the user to the right System Settings pane and shows a floating
panel they drag our `.app` into to authorize — the OS performs the grant.

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

## Why we use it
Granting **App Management** (`kTCCServiceSystemPolicyAppBundles`) has no request
API. This drives the user to the right System Settings pane and shows a floating
panel they drag our `.app` into to authorize — the OS performs the grant.

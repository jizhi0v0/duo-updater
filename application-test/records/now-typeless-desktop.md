# now.typeless.desktop (Typeless)

Single-channel (stable only). Verified on-machine 2026-06-19 with
`channel-verify "/Applications/Typeless.app"`.

| Channel | Real bundle id        | Real shortVersion | build      | Channel marker | Detected | Probe verdict |
|---------|-----------------------|-------------------|------------|----------------|----------|---------------|
| stable  | now.typeless.desktop  | 1.8.0             | 1.8.0.109  | —              | stable   | up to date (installed 1.8.0; latest 1.8.0) |

- Probe endpoint: `https://typeless-static.com/desktop-release/arm64-mac.yml` (electron-builder feed)
- Resolved download: `https://typeless-static.com/desktop-release/Typeless-1.8.0-arm64.dmg`
- Version scheme: feed `version` = `CFBundleShortVersionString` (marketing), NOT build → no `versionIsBuild`.
- One-click dmg base64 sha512 captured from the line after the dmg's `url:`; VendorInstaller same-Team gate = 947QKAND4W.

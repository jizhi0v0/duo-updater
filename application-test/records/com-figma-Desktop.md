# Figma — channel verification record

Verified 2026-06-06. Stable = installed `/Applications/Figma.app`; Beta = official
zip downloaded and extracted read-only (not installed). **Independent bundle ids
(Pattern A).** Both signed by Team `T8RA8NE3B7` (Figma, Inc.).

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `com.figma.Desktop`     | `126.4.11` | stable ✓ | `desktop.figma.com/mac-arm/RELEASE.json` → 126.4.13, **UPDATE 126.4.11→126.4.13** |
| beta    | `com.figma.DesktopBeta` | `126.6.2`  | beta ✓   | `desktop.figma.com/mac-arm/beta/RELEASE.json` → 126.6.2, **up to date** |

## Evidence
- `channel-verify "/Applications/Figma.app" --expect stable` → detection ✓, probe
  answered, download `…/Figma-126.4.13.zip`, verdict UPDATE.
- `channel-verify ".../Figma Beta.app" --expect beta` → detection ✓ (`.beta` from
  name "Figma Beta"), probe answered, download `…/beta/FigmaBeta-126.6.2.zip`.
- One-click safety: downloaded `Figma-126.4.13.zip` and `FigmaBeta-126.6.2.zip` both
  `codesign` → notarized Developer ID, `TeamIdentifier=T8RA8NE3B7`, bundle ids
  `com.figma.Desktop` / `com.figma.DesktopBeta` == the installs. VendorInstaller
  Team gate passes.

## Correction
The pre-existing `CHANNEL_COVERAGE_TODO` entry "Figma — Beta · 应用内 feature flag,
无独立下载/bundle id" was **wrong**. Figma Beta is a fully separate app with its own
bundle id and download tree. Corrected here and in the coverage doc.

## Notes
- versionPattern matches `CFBundleShortVersionString` exactly (no build/marketing trap).
- Changelog: `figma.com/release-notes` is product-wide; both channels share it.

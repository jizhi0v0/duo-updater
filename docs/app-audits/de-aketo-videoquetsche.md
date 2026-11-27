# Videoquetsche

| Field | Value |
| --- | --- |
| Bundle ID | `de.aketo.videoquetsche` |
| Developer ID team | `9H7F5NMT97` (aketo GmbH) |
| Distribution | [Official GitHub Releases](https://github.com/noestreich/videoquetsche/releases) |

## Copy groups

| Official tag | Bundle version / build | Architectures | Update channel |
| --- | --- | --- | --- |
| `v1.1.0` | `1.0` / `1` | arm64 | Stable |
| `v1.2.0` | `1.2.0` / `3` | arm64, x86_64 | Stable |
| `v1.2.1` | `1.2.1` / `4` | arm64, x86_64 | Stable |

On 2026-11-27, these were all public tags and releases. Each official ZIP had
the same bundle ID and Developer ID team, passed signature and notarization
checks, and declared macOS 13 as its minimum. None declared a Sparkle feed or
contained a Sparkle framework, login item, or XPC helper.

## Detection, release notes, and installation

- The built-in GitHub rule reads stable numeric `v` tags, including future
  major releases. A suffix such as `v1.3.0-rc.1` falls outside the rule.
- The structured changelog uses the official release bodies. Its current
  entry is 1.2.1.
- One-click selects the exact `Videoquetsche.zip` asset and uses the existing
  GitHub digest check and Developer ID, bundle ID, and version checks.
  The lowest observed installed version is 1.0, from the `v1.1.0` archive.

## Nightly verification

The GitHub and changelog registries each select one entry for
`duo verify --github --changelog --only de.aketo.videoquetsche --no-installed`.
Both passed against the live feed on 2026-11-27.

`duo verify-install --only de.aketo.videoquetsche` selected
`github:noestreich/videoquetsche:stable` and downloaded and inspected the
1.2.1 ZIP on an Apple Silicon Mac running macOS 27.3. It reported
`de.aketo.videoquetsche / 9H7F5NMT97` with no warnings or skips.

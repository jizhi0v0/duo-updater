# Brew-first source fallback — 2026-11-06

Policy: official casks (including `auto_updates`) and third-party taps answer first.
A per-install-path menu preference, off by default, permits the existing source stack
to continue only after brew reports no newer version. A brew update wins immediately;
there is no comparison of the highest version across sources. Existing GitHub recipe,
release-channel, edition, one-click eligibility and signature gates are unchanged.

## Build and automated checks

- Release build: `xcodebuild -project App/DuoUpdater.xcodeproj -scheme DuoUpdater -configuration Release -derivedDataPath /tmp/duo-1864-build -onlyUsePackageVersionsFromResolvedFile SWIFT_COMPILATION_MODE=incremental build` — passed.
- Core: `swift test --package-path DuoUpdaterCore --filter 'ThirdPartyCaskSourceTests|HomebrewCask|SourceStorePolicy'` — 80 tests / 9 suites passed.
- App: `make test-app` — 328/328 tests passed; 1,266 localization keys reachable.
- CLI: `swift test --package-path CLI --filter SettingsGitHubSignInTests` — 5 tests passed, including preference loading into the shared checker.
- Core cases cover both tap types with auto_updates=true: off/on, brew older/equal/newer; downstream call counts; no downstream match; tap failure; and an official catalogue failure blocking only an owned copy, not an unrelated same-named app.
- Local adversarial-risk classifier on the working diff: no risk categories matched.

## VMPal validation

Guest: macOS 27.2 (26B123), Apple Silicon. Signed Release executable SHA-256:
`ac609eb03a0c23749082be6624788b7463224ebd7566886a6b06737559eee6aa`.
Code signature verification (`codesign --verify --deep --strict`) passed.

1. Handy 0.10.0, installed by official Homebrew cask with auto_updates=true:
   default-off check resolved `Homebrew → 0.10.0 [upToDate]`; row appeared in Homebrew.
2. Enabled “Check other sources when Homebrew has no update” using the workbench row menu.
   The actual check logged Homebrew 0.10.0 first, then GitHub 0.10.0. Row moved to Apps
   and displayed GitHub release notes. Popover menu showed the same checked preference.
3. Restarted DuoUpdater: the preference remained checked and the same source order
   was observed. Disabled it from the popover menu: Handy returned to Homebrew.
4. CompressO 4.1.0 from codeforreal1/tap: default-off resolved Homebrew 4.1.0;
   enabling the menu preference resolved Homebrew 4.1.0 then GitHub 4.1.0.
   Its GitHub recipe remains detection-only; this change does not add a GitHub installer.
5. Controlled lagging-tap scenario: temporarily replaced only the VM tap's cask
   definition with its real historical 4.0.0 definition, leaving installed CompressO
   and its receipt at 4.1.0. With the switch off, the row showed the lagging 4.0.0
   version but the check remained upToDate, with no downgrade update action.
   With the switch on, the check logged Homebrew 4.0.0 then GitHub 4.1.0.
6. Restored the original tap definition (clean tap git status), switched both
   preferences off, and rechecked CompressO: Homebrew 4.1.0 again.

No app package was installed, replaced or downgraded in this validation. Handy stayed
0.10.0 and CompressO stayed 4.1.0; before/after executable SHA-256 values matched.
The “brew has a newer version, do not call downstream” branch was exercised by the
Core tests, not a live package upgrade: both VM apps were already current.

Privacy: this record omits user paths, account/device identifiers, unrelated app
inventory, credentials and raw desktop screenshots. The validation build remains in
the VM; host applications were not changed.

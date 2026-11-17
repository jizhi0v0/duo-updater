# Issue #2055: VM validation

2026-11-17. VMPal macOS VM 1, Apple Silicon, macOS 27.2 (26B123), Homebrew 7.0.12. Guest clock showed November 16. Core source checkout: `57aefd45f9babb58fbb28979e25bb4854bc2e001`, also named in the issue. Relevant Homebrew source files had no working-tree changes. No production fix was made.

The issue has six numbered defect categories; its seventh checklist item requests regression coverage. Formula pin and app-cask pin were tested separately here, producing seven runtime scenarios.

## Method

`VMProbe.swift` imports the complete unmodified production Core with `@testable`, built on the host in a temporary package copy with an additional executable target, then run in the guest. The catalog uses the existing injection seam. Inventory and ownership use actual default Caskrooms, Brew-installed receipts and staged links. App descriptions are supplied for known fixture paths. These are production Core entry-point tests, not a complete shipping GUI walkthrough.

Disposable `duo-2055-*` casks were temporarily added to the VM's official tap to exercise official-source provenance checks. Minimal app archives retain the same bundle version while cask versions change. This validates record comparison and execution routing, not vendor signing or real vendor payload correctness. The local formula uses an archive with its actual SHA256.

`setup.py` preserves the initial setup script: the initial formula install failed because formula SHA256 does not accept `:no_check`. This was corrected to the actual archive checksum before successfully installing 1.0, bumping the definition to 2.0 and pinning. Its real successful outdated JSON is preserved. Intel Brew required Rosetta and writable prefix directories. Failed attempts and successful installation logs are retained.

## Results

1. **Platform variation reproduced:** fixture base version 2.0 and ARM variation 1.0. Actual Brew selects 1.0; Core returns 2.0. See `evidence/platform-info.txt`, `catalog.json`, `core-before.txt`. This tests the variation mechanism on the actual VM architecture, not the issue's historical Itsycal example on macOS 15.

2. **Old token reproduced:** install old token 1.0, rename tap definition and add real tap rename mapping. Brew recognizes the installed old record and offers new-token 2.0; Core returns nil. Ordinary Brew upgrade migrates the record; Core then resolves the same app under the new token. See `setup.log`, `core-before.txt`, `old-upgrade.log`, `old-after-migration.txt`.

3. **Formula pin reproduced:** real pinned 1.0 formula with definition 2.0 appears in Brew outdated JSON. Production parser includes it, while Brew upgrade dry run refuses it. See `formula-outdated.json`, `formula-pin-upgrade.txt`, `core-before.txt`. GUI counts/buttons were not separately driven.

4. **App-cask pin discrepancy reproduced:** real pinned 1.0 cask with definition 2.0 is offered by the app source, while the package-cask parser excludes the same pinned entry. Brew upgrade dry run refuses it. See `cask-outdated.json`, `cask-pin-upgrade.txt`, `core-before.txt`. This does not justify blocking explicitly selected updates from other sources.

5. **Full-version truncation reproduced:** Brew offers and successfully upgrades `1.0,101` to `1.0,102`. Before upgrade Core returns marketing 1.0, build nil and recorded marketing 1.0, losing the changing component. See `cask-outdated.json`, `core-before.txt`, `full-upgrade.log`.

6. **Dual prefix reproduced through actual execution:** separate Intel Brew installs fixture 1.0 into `/usr/local/Caskroom`. Core recognizes that record but selects `/opt/homebrew/bin/brew`. Real `HomebrewInstaller.upgrade`, without a path override, overwrites the existing app and creates an ARM-prefix 2.0 record. The original Intel-prefix 1.0 record remains. See `intel-install3.log`, `intel-prefix.txt`, `dual-before.txt`, `dual-upgrade.log`, `final-records.json`. Homebrew warns that x86_64 on this OS is Tier 3; the observed installation still completes.

7. **GUI shell environment reproduced at production entry points:** temporary `.zshrc` exports NO_AUTO_UPDATE=1 and AUTO_UPDATE_SECS=2055. LaunchServices launches VMProbe as a small `.app`; its initial process lacks NO_AUTO_UPDATE. Real login-shell resolver and `HomebrewConfig.read(environment:)` read disabled auto-update and interval 2055. Ordinary executor and cask fetch are then exercised against an injected logging executable: ordinary reads force NO_AUTO_UPDATE=1 but omit interval; initial cask install dry run receives neither variable; subsequent fetch forces NO_AUTO_UPDATE=1 but omits interval. See `env-result.txt`, `env-commands.log`. This captures actual argument/environment construction without real network refreshes. Shipping GUI buttons and brew.env precedence were not exercised.

Additional #2036 check: removing only the full-version fixture's staged app symlink makes Core return nil; restoring it restores ownership. See `missing-link.txt`, `link-target.txt`, `old-after-migration.txt`. This does not establish why the reporter's link disappeared, nor reproduce the original initial-offer sequence.

## Cleanup and scope

Fixture packages were unpinned/uninstalled, temporary cask definitions removed, both rename maps restored and temporary `.zshrc` removed. Rosetta and the new Intel Brew remain in the VM. No host app was replaced, no issue comment posted, and no regression fix implemented. Existing working-tree changes were preserved.

## Fixed-state VM runner

`fixed-vm.py` and `FixedVMProbe.swift` are the repeatable fixed-state acceptance
runner. They do not replace the baseline evidence above. The runner refuses
hardware whose model is not `VirtualMac*`, refuses preexisting fixture names,
and builds the complete current Core with the repository dependency lockfile
inside the VM. All its packages use the separate `duo2055vm-*` namespace.

After copying the checkout into the VM, run there (never on the host):

```sh
python3 /path/to/duo-updater/verify/issue-2055/fixed-vm.py \
  --repo /path/to/duo-updater --work /tmp/duo2055vm-fixed-20261117
```

Prerequisites are Xcode/Swift and existing separate ARM and Intel Homebrew
installations with their official cask taps, plus Rosetta. This test keeps
unsupported Intel execution out of the product: detection and the real
installer must explicitly refuse foreign-prefix ownership before running
Brew. Official and third-party Intel records and app bytes must stay unchanged.

The runner tests positive and negative controls: current platform version,
URL/artifact/dependency merge; old-token resolution, same-name unowned copy and
foreign-tap rejection; real pinned formula and cask plus live unpin; comma and
colon suffix updates that actually change bundle build 101 to 102 and then
settle current; and LaunchServices login-shell settings reaching ordinary
reads, preliminary dry run and fetch. `evidence/result.json` in its work folder
is the overall verdict; raw commands and outputs remain beside it.

Cleanup runs on failure too. Existing rc and tap rename files are backed up,
and restored only if their current bytes still equal this run's edit. A
concurrent change makes the run fail and is preserved. Only packages and
fixture paths proven absent at startup are removed. No result is claimed here
until an actual VM run is recorded.

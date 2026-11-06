# Brew ownership and pkg authentication — 2026-11-06

Follow-up to the brew-first fallback validation. Both review findings were reproduced
before the fixes and verified in an Apple Silicon macOS 27.2 (26B123) VMPal guest.
No host applications were changed.

## Actual installed-path ownership

- Kept the official Homebrew Handy 0.10.0 installation in its nested Applications
  directory. Installed a separate, genuine upstream Handy 0.9.8 DMG copy in another
  nested Applications directory; its version metadata was not edited.
- Before: the manual copy incorrectly resolved Homebrew 0.10.0 as its update.
- After: the manual copy resolved GitHub 0.10.0; the original brew-owned copy
  continued to resolve Homebrew 0.10.0, up to date.
- A subsequent GitHub-routed update of the manual test copy to 0.10.0 was observed
  in the install log. Its initiating trigger was not independently established;
  this is not recorded as a deliberate click test.
- The original brew-owned Handy executable hash remained
  `aa356164a4919c52992d347e1ead001b55536d378a80ea0dff5d1f480e35e236`.
  Its app and Homebrew installed versions remained 0.10.0.

## Actual pkg upgrade and authentication

This is a controlled local third-party cask fixture, not a vendor release. It uses
real Homebrew, pkgutil receipts, and the macOS system installer. The tiny test app
has no installer scripts or network activity.

- Local qualified cask: `duo-validation/pkg/duo-brew-pkg-probe`.
- Installed fixture 1.0 with a narrowly scoped, temporary setup-only sudo rule.
  Removed that rule and invalidated the sudo timestamp before upgrade testing.
- Changed the local cask definition to 2.0. Apps detected the pkg-installed app
  through its receipt and offered the Homebrew update.
- Before: clicking the popover's update confirmation failed with
  `sudo: a terminal is required to read the password` / `a password is required`.
  App and pkgutil receipt remained at 1.0.
- After: the same path opened DuoUpdater's Homebrew authentication panel. The user
  entered and confirmed the administrator password directly in the VM. No password
  was read, copied, logged or included in this record.
- The real upgrade completed: `applied=true`, followed by Homebrew 2.0 `upToDate`
  and `install done`. App bundle, pkgutil receipt and Homebrew installed version
  all read 2.0; Homebrew still identifies the original `duo-validation/pkg` tap.
- The popover no longer offered the fixture update. No `duo-askpass.*` temporary
  channel directory remained, and the setup-only sudo rule was confirmed absent.

## Automated checks and build

- New regressions first failed against the old behavior: unrelated manual copy
  claimed by Homebrew, and missing askpass environment (fixture exit 71).
- Core targeted Homebrew, third-party, askpass and automatic-install checks:
  **166 tests / 29 suites passed**. The authentication regression was then
  strengthened to exercise InstallCoordinator callback wiring and passed again.
- `make test-app`: **328/328 passed**; **1,266** localization keys reachable.
- CLI settings tests: **5 passed**.
- Signed Release build and strict deep code-signature verification passed.
  Verified VM executable SHA-256:
  `67be3b2b28321eab1656d2e5b7d7d66e56a0b5965f4b2f070342b0a8fb92cf94`.
- `git diff --check` passed.
- A separate local adversarial reviewer checked the shipping diff, including
  the `secrets` risk, callback wiring, cancellation and channel cleanup, automatic
  install rejection, and exact installed-path ownership. No actionable findings.
  The reviewer did not execute the tests; runtime checks above were run separately.

Privacy: only scoped text evidence is published. Personal paths, machine/account
identifiers, credentials, unrelated application inventory and desktop screenshots
are omitted. Test apps and the validation build remain in the VM.

# Homebrew #2057–#2064 repair verification

Validation date: 2026-11-17. All product builds, tests and installation checks
in this round run in the dedicated Apple Silicon macOS 27.2 VM. The host app
and the original working checkout are not used for installation checks.

## Implementation

- Keep the exact installed owner, while carrying architecture/macOS refusal
  through version results, action policy and coordinator entry checks.
- Give ordinary Brew-owned PKG updates to the existing Homebrew installer and
  BrewAskPass. Native Brew owns metadata authentication, digest verification,
  dependencies and conflicts.
- Prepare conservative manual installers with native Brew, verify the exact
  declared installer and hand it to the user. Opening it leaves `applied=false`;
  a later observed app version determines completion.
- Keep suite members in the app list with a static qualified parent link. The
  package row owns update, cancellation and errors. Reuse exact receipt/staged
  targets and the existing scanner's depth and security rules.
- Try bundle-ID/receipt fallback when filename candidates have no exact owner,
  retaining helper, copy, tap and prefix guards.
- Merge failed Brew reads with the last successful inventory, update and
  warning state. Show failure/retry while preserving Update; successful empty
  results still clear state. Formula and cask reads remain independent.

## Completed checks

- Focused Core: 232 tests in 23 suites passed.
- All Core coverage: 7,628 tests in 688 suites passed in two sequential fresh
  processes (27 App Store tests plus 7,601 remaining tests); see the full-run
  limitation below.
- App: 384 tests passed; shipping Debug extraction build passed and all 1,445
  localization keys were reachable.
- Unsigned Release: App and CLI builds and artifact/arm64 checks passed.
- CLI: 731 tests in 84 suites passed. Script checks passed. The
  `application-test` tools build passed after adding the suite status to both
  exhaustive diagnostic switches in `channel-verify`.
- Inert PKG precondition: installed app/receipt 1.0, offered 2.0, native Homebrew
  route, dependency initially absent.
- Running App compatibility checks: both Intel-only and macOS 15/26-only offers
  retained the owner and 1.0 → 2.0 version display, showed “Not compatible” with
  the actual host mismatch, and withheld Update. Restoring the compatible
  definition restored the normal major-update confirmation.
- Independent adversarial review at `5438dd9ae711366b8ad74fd66e5acdf6000184a6`:
  no remaining findings. The confirmed suite navigation finding was fixed and
  covered by exact qualified normal/unchecked-parent and absent-parent tests.
  The reviewer also checked raw VM execution/cleanup receipts against this
  record; the six reviewed risks were process-control, data-loss, privilege,
  trust, secrets and untrusted-input.

## Runtime results

- Ordinary PKG: initiated the inert 1.0 → 2.0 update in the running App. The
  actual BrewAskPass panel appeared; the user entered the VM administrator
  password directly. Native Brew installed the initially missing dependency.
  The app version, Brew installed record and system PKG receipt all became
  2.0, and the update disappeared from the App's pending list. The opt-in
  integration assertion passed.
- Conflict and digest refusals: offered 3.0 with an installed conflicting cask,
  then separately with a deliberately wrong SHA-256. Actual native Homebrew
  rejected both, and the production installer assertions verified app/Brew
  version 2.0 remained unchanged. Both opt-in checks passed.
- Manual Adobe handoff: native Brew prepared the genuine declared installer;
  code signature and Team ID `JQ525L2MZD` matched the installed app. The
  coordinator returned its staged URL with `applied=false`, one before-open
  callback and no Brew installed receipt. Accepted macOS's normal Gatekeeper
  Open prompt, observed the real installer finish, then closed its window.
  Post-inspection still found app version 2026.10.66 with a valid signature.
  The seed install's detector initially triggered the existing nested-app
  guard; stopping that exact task-created launch agent allowed the handoff.
  All recorded Adobe fixture paths were cleaned up afterward.
- Genuine Racket suite: installed 9.2, then offered 9.3. The normal app list
  showed DrRacket, PLT Games and Slideshow with static parent ownership and no
  independent update action. DrRacket's parent link opened the exact `racket`
  package row on the CLI tab. Updating only that row upgraded all three apps
  to 9.3, removed the old 9.2 directory and settled the Brew record at 9.3.
  Before/after production integration assertions passed with one package row,
  one owner covering the three exact paths and zero downstream source calls.
- Failed-read recovery: the temporary cask explicitly aborted native
  `brew info --json=v2 --installed` and `brew outdated --cask --json=v2`; both
  returned status 1. The running App retained the 1.0 → 2.0 offer, installed
  rows, enabled Update and deprecation warning, added “Check failed — showing
  last results” with Retry, and showed the failure in the popover's Homebrew
  summary. Restoring the definition and clicking Retry removed the error while
  preserving the offer and warning. Both recovered native reads returned 0.
  Ordinary Ruby exceptions had fallen back to installed metadata with status
  0; those initial attempts are not counted as failed-read verification.

All four cleanup manifests report no recorded leftovers, including the
disposable tap, apps, cask records, system PKG receipt and Adobe launch agent.
The task's Debug app was stopped; the canonical VM app was not launched.

## Full Core validation

The first monolithic run executed 7,628 tests and failed. One old Team-ID
fixture declared manual installation without the explicit installer path; that
fixture was corrected to represent the new manual route, retaining both signed
positive and unsigned negative controls, and all 11 tests passed.

The other failure was the unchanged App Store batch-language test. The VM's
existing test-process log recorded an HTTP 400 for `lang=en_cn`, followed by
the existing process-wide language-rejection latch. That suppressed the later
test's expected language parameter. No App Store source or test was changed.
Its 27-test suite passed in a fresh process. The runner's existing `core-rest`
step passed all 7,601 remaining tests in another process. Together these runs
cover the same 7,628 tests and 688 suites as the monolithic run.
The recorded EventStore schema issue is an existing known issue, not an
unexpected failure. The monolithic failure is retained rather than reported
as a passing run.

The sanitized run receipts are in [results.json](results.json). A source
comparison against `5438dd9ae711366b8ad74fd66e5acdf6000184a6` checked all 64
changed tracked files in the VM snapshot with no mismatches. This README and
the receipt summary are evidence-only additions after that reviewed source.

## Fixture scope and limits

`pkg-fixture.py` uses an inert third-party cask. It checks the shared native
installer/AskPass behavior; third-party PKG updates already used Brew before
this change. Official source tests separately distinguish removal of the old
direct-PKG route. It is not an official vendor old-to-new installation claim.

`manual-fixture.py` pins a genuine signed Adobe installer. Its opt-in test uses
an already installed same-version app and a controlled update status. It checks
preparation and handoff, not source detection or an Adobe old-to-new update.

`racket-suite-fixture.py` uses genuine Racket 9.2/9.3 downloads. The historical
9.2 cask's ARM digest is replaced only with the current vendor-published digest
for the re-signed release, as recorded in `racket-packages.json`. Digest checks
remain enabled.

`read-fixture.py` uses an inert app-less cask and an explicit Ruby abort in its
own definition to make native Brew reads fail. It never replaces Brew itself.

Manual and read fixture cleanup must precede PKG cleanup because they share
the disposable fixture tap. Scripts refuse preexisting fixture paths; cleanup
targets only the paths/receipts recorded by this task. Raw VM screenshots and
machine-specific logs remain local.

# Third-party `:latest` fallback — 2026-11-11

Issue: https://github.com/jizhi0v0/duo-updater/issues/1946

## Real macOS integration

- Apple Silicon, macOS 27.3; Homebrew 7.0.13-69-g2ea376f.
- Downloaded the vendor's Brow 1.0.77-beta and 1.0.78-beta ZIPs and extracted
  them with `ditto`; the current package passed `codesign --verify --deep --strict`.
  Neither application was launched or installed.
- Copied the vendor's public `brow.rb` into a temporary local test tap,
  `duo-issue1946/tap`. The cask retained `version :latest` and its vendor URL.
  Tap trust was isolated under a task-specific `XDG_CONFIG_HOME`.
- Created an isolated Caskroom receipt and app symlink for each extracted copy.
  `AppScanner` read the real bundles; the production `ThirdPartyCaskSource`
  used its default executor to run real `brew info --json=v2 --cask` against
  the local tap. Its returned token, tap and version were `brow`,
  `duo-issue1946/tap` and `latest`; this response was not stubbed.
- A standalone executable called the production `UpdateChecker` with this
  source followed by an instrumented wrapper around `SparkleAppcastSource`.
  Sparkle fetched the live vendor feed. This validates the changed Core path;
  it is not a GUI interaction or an invocation of `duo check`.

Baseline `eb90f298c` failed all eight assertions: the two versions, each with
fallback off, per-copy allowed, globally allowed or explicitly Homebrew-only,
returned the tap availability/trust error, no owner and zero Sparkle calls.

After the fix, all eight passed:

- Per-copy/global allowance: 1.0.77-beta offered 1.0.78-beta; 1.0.78-beta
  reported up to date. Each made one Sparkle call.
- Default off/explicit Homebrew-only: neither called Sparkle or claimed to be
  current. Both explained that `version :latest` supplies no comparable version.
- Every result retained `duo-issue1946/tap/brow` as its Homebrew owner.

The selected raw output is in [runtime.txt](runtime.txt). The temporary tap was
removed afterwards. No existing app, installation receipt or user preference
was overwritten; the installed DuoUpdater app and CLI were not replaced.

## Regression coverage

The new tests fail on the baseline (28 assertion failures), then pass with the
fix. Focused Homebrew/source-policy/signing coverage passed 110 tests in 10
suites. Cases include global and per-copy choices, Homebrew-only overriding a
global allowance, no downstream answer, another tap returning `latest`,
migration to an official self-updating cask, digest-only fallback and a
previous signature refusal. Existing unreadable/wrong-tap and failed-command
cases still prevent fallback.

The GUI and duo CLI share this Core checker; no separate source-order or
installation-policy change is made.

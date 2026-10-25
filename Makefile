.PHONY: install cli build test test-scripts test-swift test-app test-release gallery notarize release check-python

# Build and test only the dependency revisions committed in each package's
# Package.resolved. Without it SwiftPM re-resolves whenever a manifest's range
# allows something newer, and rewrites the lockfile, so what a local build or
# `make test` compiles can differ from what was reviewed. With it, a stale
# lockfile is an error instead of a silent update.
RESOLVED_ONLY := --force-resolved-versions

# Build with a stable Developer ID signature and deploy the canonical copy to
# /Applications. See scripts/install.sh for why the identity matters (TCC grants).
install:
	@scripts/install.sh

# Build `duo` with the same Developer ID identity and install it to a fixed
# path — an App Management grant is bound to both. See scripts/build-cli.sh.
cli:
	@scripts/build-cli.sh

# Compile the Core package. Nothing is executed — `make test` is the one that
# runs anything, and it runs more than this package.
build:
	cd DuoUpdaterCore && swift build $(RESOLVED_ONLY)

# CLI and application-test both depend on DuoUpdaterCore by path. Each would
# compile all of Core again into its own .build, so they share Core's .build
# instead. Measured cold on a 14-core Mac 2026-09-15, CPU time: CLI 92 s -> 34 s,
# application-test 68 s -> 8.5 s. Rebuilding Core's tests afterwards
# (`swift build --build-tests`) rebuilt nothing (1.3 s), so switching the root
# package does not throw the cache away. That holds while all three packages
# resolve the same dependency pins.
#
# Split in three so CI can run each part as its own job (.github/workflows/ci.yml).
# The parts share nothing: test-scripts only reads the source tree, and
# test-swift and test-app build into different directories (SwiftPM's .build
# versus app-tests' derived data). `make test` runs all three at once, each into
# its own log — see scripts/test-parts.sh for the measurement and the output.
test:
	@MAKE="$(MAKE)" scripts/test-parts.sh test-scripts test-swift test-app

# The Python every recipe here runs, and app-tests.sh through the export: the
# first of python3, python3.15 … python3.10 that is at least 3.10. Picked here
# rather than left to PATH because the machines disagree on what `python3` is:
# the mini's duoupdater runners put uv's 3.12 first on PATH, the hosted image's
# python3 passes the 3.10 floor below, and a Mac's /usr/bin/python3 is 3.9.6
# with Homebrew's 3.14 only as python3.14 (2026-10-11). 3.10 is the floor because
# test_app_test_coverage.py's encoding test needs `-X warn_default_encoding`, and
# on 3.9 it passes without checking anything.
PYTHON := $(shell for p in python3 python3.15 python3.14 python3.13 python3.12 python3.11 python3.10; do \
	command -v $$p >/dev/null 2>&1 && $$p -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && { command -v $$p; exit 0; }; \
	done)
export PYTHON

check-python:
	@test -n "$(PYTHON)" || { \
	  echo "✗ No Python 3.10 or newer on PATH (python3 is: $$(python3 --version 2>&1 || echo missing))." >&2; \
	  echo "  Put one there as python3 or python3.1x, e.g. brew install python@3.14." >&2; \
	  exit 1; }

# The Python gates and their own tests. Seconds, and no build.
test-scripts: check-python
	$(PYTHON) scripts/test_appcast_edit.py
	$(PYTHON) scripts/test_publish_release.py
	$(PYTHON) scripts/test_notarize_pins.py
	$(PYTHON) scripts/test_pinned_xcodegen.py
	$(PYTHON) scripts/test_derived_data_path.py
	$(PYTHON) scripts/test_homebrew_tap.py
	$(PYTHON) scripts/test_sunset_sweep.py
	$(PYTHON) scripts/test_site_floor.py
	$(PYTHON) scripts/test_ci_route.py
	$(PYTHON) scripts/test_recipe_autofix_check.py
	$(PYTHON) scripts/test_runner_hook.py
	$(PYTHON) scripts/test_ci_build_cache.py
	$(PYTHON) scripts/test_check_prose_claims.py
	$(PYTHON) scripts/test_check_offpool.py
	$(PYTHON) scripts/test_check_recipe_snapshots.py
	$(PYTHON) scripts/test_check_swift_backdeploy.py
	$(PYTHON) scripts/test_claude_lag_probe.py
	$(PYTHON) scripts/test_app_test_coverage.py
	$(PYTHON) scripts/test_check_localizable_specifiers.py
	$(PYTHON) scripts/check_localizable_specifiers.py
	$(PYTHON) scripts/check_staged_version_use.py
	$(PYTHON) scripts/test_check_staged_version_use.py
	$(PYTHON) scripts/check_cli_concurrency_gates.py
	$(PYTHON) scripts/test_check_cli_concurrency_gates.py
	$(PYTHON) scripts/check_app_audits.py
	$(PYTHON) scripts/check_recipe_snapshots.py
	$(PYTHON) scripts/check_engine_notes.py
	$(PYTHON) scripts/check_skill_docs.py
	$(PYTHON) scripts/check_prose_claims.py
	$(PYTHON) scripts/test_check_digest_only_names.py
	$(PYTHON) scripts/check_digest_only_names.py
	$(PYTHON) scripts/check_offpool.py
	$(PYTHON) scripts/test_check_github_gate.py
	$(PYTHON) scripts/check_github_gate.py
	$(PYTHON) scripts/test_check_ifchange.py
	$(PYTHON) scripts/check_ifchange.py
	$(PYTHON) scripts/test_check_real_machine_record.py

# Extra `swift test` arguments for Core's suite, here and in test-release. Empty by
# default. ci.yml sets `--skip installPipelineDryRun` on the mini: that test
# downloads the first installed Sparkle app with a pending update (IINA, 110 MB,
# twice per run there), and the mini's nightly sweep already runs it over every
# candidate. A hosted runner has no Sparkle apps, so it skipped itself there anyway.
CORE_TEST_FLAGS ?=

# The two SwiftPM packages, plus the application-test harness built against them.
test-swift:
	cd DuoUpdaterCore && swift test $(RESOLVED_ONLY) $(CORE_TEST_FLAGS)
	swift test --package-path CLI --scratch-path DuoUpdaterCore/.build $(RESOLVED_ONLY)
	swift build --package-path application-test --scratch-path DuoUpdaterCore/.build $(RESOLVED_ONLY)

# App/Sources through xcodebuild. check_localizable_keys.py builds the app again
# with loc-string emission on, and reads the .xcodeproj app-tests.sh generates.
test-app: check-python
	@scripts/app-tests.sh
	$(PYTHON) scripts/check_localizable_keys.py

# Core's suite against an optimized DuoUpdaterCore — ci.yml's `release` job. Not
# part of `make test`. The native build system is required, not a preference:
# see the test target in DuoUpdaterCore/Package.swift.
test-release:
	swift test --package-path DuoUpdaterCore -c release --build-system native $(RESOLVED_ONLY) $(CORE_TEST_FLAGS)

# Render every row state to verify/row-states/<surface>/*.png. The images are
# committed:
# re-run after a UI change and read the diff. Fails if a state draws nothing.
gallery:
	@scripts/row-state-gallery.sh

# The notarytool keychain profile both targets below need. Not a secret — the
# credentials it names live in the keychain; this is only which of them to use.
# `?=` so a one-off `NOTARYTOOL_PROFILE=other make release` still wins. Without a
# default, `make release` fails at the first step every time, which is exactly how
# v0.3.47 burned a run.
NOTARYTOOL_PROFILE ?= duoupdater-notary
export NOTARYTOOL_PROFILE

# Build a notarization-ready Release app, submit it with notarytool, staple it,
# and emit dist/DuoUpdater-notarized.zip.
notarize:
	@scripts/notarize.sh

# Build, notarize, and publish a GitHub Release (`RELEASE_REPO`, this repository).
release:
	@scripts/publish-release.sh

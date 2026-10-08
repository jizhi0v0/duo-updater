.PHONY: install cli build test test-scripts test-swift test-app test-release gallery notarize release

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
	cd DuoUpdaterCore && swift build

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
# versus app-tests' derived data). `make test` runs all three, cheapest first.
test: test-scripts test-swift test-app

# The Python gates and their own tests. Seconds, and no build.
test-scripts:
	python3 scripts/test_appcast_edit.py
	python3 scripts/test_publish_release.py
	python3 scripts/test_site_floor.py
	python3 scripts/test_check_prose_claims.py
	python3 scripts/test_check_offpool.py
	python3 scripts/test_check_recipe_snapshots.py
	python3 scripts/test_check_swift_backdeploy.py
	python3 scripts/test_claude_lag_probe.py
	python3 scripts/test_app_test_coverage.py
	python3 scripts/test_check_localizable_specifiers.py
	python3 scripts/check_localizable_specifiers.py
	python3 scripts/check_staged_version_use.py
	python3 scripts/test_check_staged_version_use.py
	python3 scripts/check_app_audits.py
	python3 scripts/check_recipe_snapshots.py
	python3 scripts/check_engine_notes.py
	python3 scripts/check_skill_docs.py
	python3 scripts/check_prose_claims.py
	python3 scripts/check_offpool.py

# Extra `swift test` arguments for Core's suite, here and in test-release. Empty by
# default. ci.yml sets `--skip installPipelineDryRun` on the mini: that test
# downloads the first installed Sparkle app with a pending update (IINA, 110 MB,
# twice per run there), and the mini's nightly sweep already runs it over every
# candidate. A hosted runner has no Sparkle apps, so it skipped itself there anyway.
CORE_TEST_FLAGS ?=

# The two SwiftPM packages, plus the application-test harness built against them.
test-swift:
	cd DuoUpdaterCore && swift test $(CORE_TEST_FLAGS)
	swift test --package-path CLI --scratch-path DuoUpdaterCore/.build
	swift build --package-path application-test --scratch-path DuoUpdaterCore/.build

# App/Sources through xcodebuild. check_localizable_keys.py builds the app again
# with loc-string emission on, and reads the .xcodeproj app-tests.sh generates.
test-app:
	@scripts/app-tests.sh
	python3 scripts/check_localizable_keys.py

# Core's suite against an optimized DuoUpdaterCore — ci.yml's `release` job. Not
# part of `make test`. The native build system is required, not a preference:
# see the test target in DuoUpdaterCore/Package.swift.
test-release:
	swift test --package-path DuoUpdaterCore -c release --build-system native $(CORE_TEST_FLAGS)

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

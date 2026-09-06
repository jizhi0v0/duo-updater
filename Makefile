.PHONY: install cli build test gallery notarize release

# Build with a stable Developer ID signature and deploy the canonical copy to
# /Applications. See scripts/install.sh for why the identity matters (TCC grants).
install:
	@scripts/install.sh

# Build `duo` with the same Developer ID identity and install it to a fixed
# path — an App Management grant is bound to both. See scripts/build-cli.sh.
cli:
	@scripts/build-cli.sh

# Core package build + tests (some tests hit the network).
build:
	cd DuoUpdaterCore && swift build

test:
	python3 scripts/test_appcast_edit.py
	python3 scripts/test_publish_release.py
	python3 scripts/test_claude_lag_probe.py
	cd DuoUpdaterCore && swift test
	swift test --package-path CLI
	@scripts/app-tests.sh
	python3 scripts/check_localizable_keys.py
	python3 scripts/check_staged_version_use.py
	python3 scripts/test_check_staged_version_use.py
	python3 scripts/check_app_audits.py

# Render every row state to verify/row-states/*.png. The images are committed:
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

# Build, notarize, and publish a GitHub Release into the public binary-only repo.
release:
	@scripts/publish-release.sh

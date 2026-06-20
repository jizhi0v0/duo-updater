.PHONY: install build test notarize release

# Build with a stable Developer ID signature and deploy the canonical copy to
# /Applications. See scripts/install.sh for why the identity matters (TCC grants).
install:
	@scripts/install.sh

# Core package build + tests (some tests hit the network).
build:
	cd DuoUpdaterCore && swift build

test:
	cd DuoUpdaterCore && swift test

# Build a notarization-ready Release app, submit it with notarytool, staple it,
# and emit dist/DuoUpdater-notarized.zip.
notarize:
	@scripts/notarize.sh

# Build, notarize, and publish a GitHub Release into the public binary-only repo.
release:
	@scripts/publish-release.sh

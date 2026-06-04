.PHONY: install build test

# Build with a stable Developer ID signature and deploy the canonical copy to
# /Applications. See scripts/install.sh for why the identity matters (TCC grants).
install:
	@scripts/install.sh

# Core package build + tests (some tests hit the network).
build:
	cd DuoUpdaterCore && swift build

test:
	cd DuoUpdaterCore && swift test

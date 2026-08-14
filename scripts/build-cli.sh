#!/usr/bin/env bash
#
# Build `duo` with a stable Developer ID signature and install it to a FIXED
# path.
#
# Both halves of that matter, and for the same reason: macOS binds an App
# Management grant to the binary's designated requirement *and its path*. An
# ad-hoc signature (which is all `swift build` produces) re-pins the grant to a
# new CDHash on every rebuild; installing somewhere different starts over at
# notDetermined. So this builds through XcodeGen, runs the same signature gate
# `make install` runs, and always lands on the same path.
#
# ~/.local/libexec is deliberate over /usr/local/libexec: it is just as stable
# and needs no admin password, which the 2026-08-09 TCC spike settled.
#
# Usage:  make cli   (or)   scripts/build-cli.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO/App"
DD="${DERIVED_DATA:-/tmp/duo-cli-dd}"
PRODUCT="$DD/Build/Products/Release/duo-cli"
LIBEXEC="$HOME/.local/libexec"
BIN="$HOME/.local/bin"
DEST="$LIBEXEC/duo"
LINK="$BIN/duo"
# The Developer ID team the build signs with, and the identity every gate in
# this script checks against. A fork must set DUO_TEAM_ID to its own team --
# see README "Building from source". Exported so App/project.yml picks it up.
TEAM="${DUO_TEAM_ID:-RS59HDH7Y3}"
export DUO_TEAM_ID="$TEAM"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodegen >/dev/null || die "xcodegen not found — brew install xcodegen"

say "Generating Xcode project from App/project.yml"
( cd "$APP_DIR" && xcodegen generate >/dev/null )

say "Building Release (Developer ID signing)"
xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
           -scheme duo-cli -configuration Release \
           -derivedDataPath "$DD" build >/dev/null

[ -f "$PRODUCT" ] || die "build produced no binary at $PRODUCT"

say "Verifying signature identity"
"$REPO/scripts/verify-signature.sh" "$PRODUCT" "$TEAM"

# Replace in place rather than rm-then-copy: a grant follows the path, and an
# unlink briefly leaves that path empty. `cp` over the existing inode keeps the
# entry the TCC record refers to.
say "Installing to $DEST"
mkdir -p "$LIBEXEC" "$BIN"
cp -f "$PRODUCT" "$DEST"
chmod 755 "$DEST"
ln -sf "$DEST" "$LINK"

codesign --verify --strict "$DEST" 2>/dev/null \
    || die "the deployed copy failed signature verification"

say "Installed"
printf '   %s\n   %s -> %s\n\n' "$DEST" "$LINK" "$DEST"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) printf '\033[1;33m!  %s is not on your PATH — add it to use `duo` by name.\033[0m\n\n' "$BIN" ;;
esac

cat <<EOF
"duo install" replaces app bundles, which needs App Management. The grant is
per binary AND per path, so grant this exact file:

  System Settings ▸ Privacy & Security ▸ App Management ▸ +
  $DEST

Then confirm with:

  duo doctor

Note that running duo from a terminal can report a grant it does not hold — a
process started from a shell is normally the shell's responsibility, and duo
doctor says so when that is what it sees.
EOF

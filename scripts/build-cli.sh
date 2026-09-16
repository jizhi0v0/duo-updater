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
# Per checkout, and the dead ones reclaimed — see scripts/derived_data_path.py,
# which install.sh, app-tests.sh and row-state-gallery.sh already go through.
# This used to be a fixed /tmp/duo-cli-dd shared by every worktree open at once,
# which is a couple of dozen here: two concurrent builds collide on one
# derived-data directory's SQLite lock, and the failure reads as a broken build
# rather than as contention. Two runs in the SAME checkout still share it — the
# one collision left, and not worth a lock. `DERIVED_DATA` overrides.
DD="${DERIVED_DATA:-$(python3 "$REPO/scripts/derived_data_path.py" cli "$REPO")}"
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

# The deployment target is macOS 15, and `duo` is installed as a lone file: a
# Swift back-deployment library it links (swift-subprocess brings in `Span`) has
# nowhere to come from on an older OS. See the script.
say "Verifying it needs no Swift runtime library macOS 15 lacks"
python3 "$REPO/scripts/check_swift_backdeploy.py" "$PRODUCT"

# Copy beside the destination, then rename over it -- never `cp` onto it. The
# kernel caches a binary's signature per file and does not flush that cache when
# the contents are rewritten in place, so a `cp` over a copy that is still
# running leaves every later launch killed with "Code Signature Invalid" while
# `codesign -v` calls the file valid; a new file clears it without a restart. Apple:
# https://developer.apple.com/documentation/security/updating-mac-software
# The rename also keeps the path from ever being empty, which is what an
# rm-then-copy would get wrong: a grant follows the path. The system TCC.db
# `access` table keys a grant by client path plus csreq and has no inode column
# (schema read 2026-09-13). That a grant survives the rename is inferred from
# that, not tested: there was no App Management grant on this path to test with.
say "Installing to $DEST"
mkdir -p "$LIBEXEC" "$BIN"
TMP="$(mktemp "$DEST.XXXXXX")"
cp -f "$PRODUCT" "$TMP"
chmod 755 "$TMP"
mv -f "$TMP" "$DEST"
ln -sf "$DEST" "$LINK"

codesign --verify --strict "$DEST" 2>/dev/null \
    || die "the deployed copy failed signature verification"

# What this binary was built from, beside the binary, so `duo verify` can refuse to
# sweep with recipes that are not the ones in the reader's tree. The recipes are
# compiled in and the report gives no sign of which ones it used, so a stale binary
# produces a full, normal-looking answer about rules that were replaced hours ago --
# twice now, in both directions. See CLI/Sources/DuoKit/SourceStamp.swift.
#
# Asked of the binary rather than hashed here: one definition of the digest, so the
# side that writes it and the side that checks it cannot drift apart. Written via a
# temporary file so a failure leaves the previous stamp rather than an empty one --
# an empty stamp reads as "no record", which is a refusal the next person would have
# to debug instead of just rebuilding.
say "Recording the sources it was built from"
STAMP="$DEST.built-from"
( cd "$REPO" && "$DEST" verify --source-digest ) > "$STAMP.new" \
    || die "could not digest the sources under $REPO"
mv -f "$STAMP.new" "$STAMP"

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

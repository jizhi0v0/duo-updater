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
# Recipe families written as data (`.json5`) are not in the binary: SwiftPM builds
# them into this resource bundle, and `Bundle.module` looks for it beside the
# executable (`Bundle.main.bundleURL`). A binary copied without it traps on first
# use of the recipe index ("unable to find bundle named …", exit 133).
RESOURCE_BUNDLE="DuoUpdaterCore_DuoUpdaterCore.bundle"
PRODUCT_BUNDLE="$DD/Build/Products/Release/$RESOURCE_BUNDLE"
RECIPE_SOURCE="$REPO/DuoUpdaterCore/Sources/DuoUpdaterCore/Resources/Recipes"
LIBEXEC="$HOME/.local/libexec"
BIN="$HOME/.local/bin"
DEST="$LIBEXEC/duo"
LINK="$BIN/duo"
BUNDLE_DEST="$LIBEXEC/$RESOURCE_BUNDLE"
STAMP="$DEST.built-from"
# The Developer ID team the build signs with, and the identity every gate in
# this script checks against. A fork must set DUO_TEAM_ID to its own team --
# see README "Building from source". Exported so App/project.yml picks it up.
TEAM="${DUO_TEAM_ID:-RS59HDH7Y3}"
export DUO_TEAM_ID="$TEAM"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Staging paths made below are removed on any exit; after a successful rename the
# path no longer exists and removing it is a no-op.
BUNDLE_TMP=""
TMP=""
cleanup() {
    if [ -n "$BUNDLE_TMP" ]; then rm -rf "$BUNDLE_TMP"; fi
    if [ -n "$TMP" ]; then rm -f "$TMP"; fi
    rm -f "$STAMP.new"
}
trap cleanup EXIT

# The digest of the recipe data, over name, length and bytes of every family file
# (scripts/recipe_digest.py; RecipeFamilyFile.digest computes the same at runtime).
# It goes into the build, where it lands in the binary's embedded Info.plist and so
# under its signature: the bundle installed beside `duo` is outside that signature
# and writable by whoever runs it, and a `duo` holding an App Management grant must
# refuse recipe files it was not built with. Taken BEFORE the build, so everything
# below is checked against the one tree the binary was told about.
recipe_digest() { python3 "$REPO/scripts/recipe_digest.py" "$1"; }
say "Digesting the recipe data"
RECIPE_DIGEST="$(recipe_digest "$RECIPE_SOURCE")" || die "the recipe directory $RECIPE_SOURCE cannot be digested"

command -v xcodegen >/dev/null || die "xcodegen not found — brew install xcodegen"

say "Generating Xcode project from App/project.yml"
( cd "$APP_DIR" && xcodegen generate >/dev/null )

say "Building Release (Developer ID signing)"
xcodebuild -project "$APP_DIR/DuoUpdater.xcodeproj" \
           -scheme duo-cli -configuration Release \
           -derivedDataPath "$DD" DUO_RECIPE_DIGEST="$RECIPE_DIGEST" build >/dev/null

[ -f "$PRODUCT" ] || die "build produced no binary at $PRODUCT"
[ -d "$PRODUCT_BUNDLE" ] || die "build produced no resource bundle at $PRODUCT_BUNDLE"

say "Verifying signature identity"
"$REPO/scripts/verify-signature.sh" "$PRODUCT" "$TEAM"

# The deployment target is macOS 14, and `duo` is installed as a lone file: a
# Swift back-deployment library it links (swift-subprocess brings in `Span`) has
# nowhere to come from on an older OS. See the script.
say "Verifying it needs no Swift runtime library macOS 14 lacks"
python3 "$REPO/scripts/check_swift_backdeploy.py" "$PRODUCT"

# Everything is verified on the build products before anything is installed, so a
# failure here leaves the previous `duo`, its bundle and its stamp as they were.
say "Verifying the recipe data the build carries"
EMBEDDED_DIGEST="$(launchctl plist __TEXT,__info_plist "$PRODUCT" 2>/dev/null \
    | sed -n 's/^[[:space:]]*"DuoRecipeDigest" = "\(.*\)";$/\1/p')" || true
[ "$EMBEDDED_DIGEST" = "$RECIPE_DIGEST" ] \
    || die "the binary carries recipe digest '${EMBEDDED_DIGEST:-<none>}', not $RECIPE_DIGEST (is INFOPLIST_FILE still set for duo-cli in App/project.yml?)"
PRODUCT_RECIPES="$PRODUCT_BUNDLE/Contents/Resources/Recipes"
BUILT_DIGEST="$(recipe_digest "$PRODUCT_RECIPES")" || die "the built bundle's recipe directory cannot be digested"
[ "$BUILT_DIGEST" = "$RECIPE_DIGEST" ] \
    || die "the recipe files in $PRODUCT_RECIPES differ from the ones the binary was built with"

# What this binary was built from, beside the binary, so `duo verify` can refuse to
# sweep with recipes that are not the ones in the reader's tree. The recipes ship
# with the binary and the report gives no sign of which ones it used, so a stale binary
# produces a full, normal-looking answer about rules that were replaced hours ago --
# twice now, in both directions. See CLI/Sources/DuoKit/SourceStamp.swift.
#
# Asked of the binary rather than hashed here: one definition of the digest, so the
# side that writes it and the side that checks it cannot drift apart.
#
# Its race with the recipe data, closed by order rather than by a lock. The stamp is
# taken of the checkout FIRST, then the checkout's recipe digest is taken again and
# must still be the one the binary was built with — so an edit before the stamp is
# caught here — and after installing, the stamp is taken again and must be equal —
# so an edit after this point is caught there. The stamp that is written is the
# one both agree on.
say "Recording the sources it was built from"
SOURCE_STAMP="$( cd "$REPO" && "$PRODUCT" verify --source-digest )" \
    || die "could not digest the sources under $REPO"
[ "$(recipe_digest "$RECIPE_SOURCE")" = "$RECIPE_DIGEST" ] \
    || die "the recipe files in $RECIPE_SOURCE changed during the build — run make cli again"

# Staged beside the destinations first, then swapped in back to back: the bundle
# renamed over the removed previous one (never copied over it, which would keep a
# deleted family's file), then the binary. `mktemp -d` makes a 0700 directory, so
# the bundle gets ordinary permissions before it is renamed in.
#
# The binary is copied beside the destination, then renamed over it -- never `cp`
# onto it. The kernel caches a binary's signature per file and does not flush that
# cache when the contents are rewritten in place, so a `cp` over a copy that is
# still running leaves every later launch killed with "Code Signature Invalid" while
# `codesign -v` calls the file valid; a new file clears it without a restart. Apple:
# https://developer.apple.com/documentation/security/updating-mac-software
# The rename also keeps the path from ever being empty, which is what an
# rm-then-copy would get wrong: a grant follows the path. The system TCC.db
# `access` table keys a grant by client path plus csreq and has no inode column
# (schema read 2026-09-13). That a grant survives the rename is inferred from
# that, not tested: there was no App Management grant on this path to test with.
say "Installing to $DEST"
mkdir -p "$LIBEXEC" "$BIN"
BUNDLE_TMP="$(mktemp -d "$BUNDLE_DEST.XXXXXX")"
ditto "$PRODUCT_BUNDLE" "$BUNDLE_TMP"
chmod 755 "$BUNDLE_TMP"
TMP="$(mktemp "$DEST.XXXXXX")"
cp -f "$PRODUCT" "$TMP"
chmod 755 "$TMP"

rm -rf "$BUNDLE_DEST"
mv "$BUNDLE_TMP" "$BUNDLE_DEST"
mv -f "$TMP" "$DEST"
ln -sf "$DEST" "$LINK"

codesign --verify --strict "$DEST" 2>/dev/null \
    || die "the deployed copy failed signature verification"
[ "$(recipe_digest "$BUNDLE_DEST/Contents/Resources/Recipes")" = "$RECIPE_DIGEST" ] \
    || die "the installed recipe files differ from the ones the binary was built with"

# Written via a temporary file so a failure leaves the previous stamp rather than an
# empty one -- an empty stamp reads as "no record", which is a refusal the next
# person would have to debug instead of just rebuilding.
( cd "$REPO" && "$DEST" verify --source-digest ) > "$STAMP.new" \
    || die "could not digest the sources under $REPO"
[ "$(cat "$STAMP.new")" = "$SOURCE_STAMP" ] \
    || die "the sources under $REPO changed while installing, so this duo's stamp would describe a tree it was not built from — run make cli again"
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

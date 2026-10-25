#!/usr/bin/env bash
#
# Print the path of a hash-verified XcodeGen binary, fetching it first if needed.
#
#   xcodegen="$(scripts/pinned-xcodegen.sh)" && "$xcodegen" generate
#
# Why not the xcodegen on PATH: the .xcodeproj it writes is a build input, and
# the scripts that run it (notarize.sh, publish-release.sh, install.sh,
# build-cli.sh) have a Developer ID identity in reach — publish-release.sh the
# Sparkle EdDSA key as well. Whatever `xcodegen` resolves to (a replaced file, a
# brew formula that moved) can plant a run-script phase in that project. Fixing
# the bytes is the only thing that closes this, so the bytes are fixed here.
#
# This file is the ONE place the version and digest are written. Every workflow
# that needs XcodeGen calls this script (test_pinned_xcodegen.py enforces that),
# so bumping means editing the two values below together. 2.46.0 is the latest
# GitHub release when this was pinned; the digest is the one GitHub publishes for
# that release's xcodegen.zip asset.
#
# What it does, in order:
#   1. Cache directory: ~/Library/Caches/duo-updater, per user. It must be a real
#      directory (not a symlink), owned by the caller, and writable by no one
#      else — otherwise another local user could swap the zip between runs.
#   2. Work on a private copy of the zip (mktemp -d, mode 700), never on the
#      cached file in place, so a swap after the hash check cannot matter.
#   3. A cached zip is RE-HASHED on every run. If it no longer matches it is
#      discarded and downloaded again; a freshly downloaded zip that does not
#      match is an error, and nothing from it is kept.
#   4. The zip is unpacked fresh on every run, so an edited unpacked binary is
#      replaced rather than trusted. (Two runs at the same instant could trip over
#      each other's unpack; the release path never does that.)
#
# stdout is the path and nothing else; progress goes to stderr.
#
# DUO_XCODEGEN_TEST_URL replaces the download URL. It exists for
# test_pinned_xcodegen.py (a local file:// zip, so no test touches the network)
# and is not a way around the pin: the digest check applies to whatever it serves.
set -euo pipefail

XCODEGEN_VERSION="2.46.0"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"

URL="${DUO_XCODEGEN_TEST_URL:-https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip}"

note() { printf 'pinned-xcodegen: %s\n' "$*" >&2; }
fail() { printf 'pinned-xcodegen: ✗ %s\n' "$*" >&2; exit 1; }

[ -n "${HOME:-}" ] && [ "${HOME#/}" != "$HOME" ] || fail "HOME is not set to an absolute path"

# A directory this user owns, that is not a symlink, and that group and others
# cannot write to.
check_private_dir() {
    local d="$1" mode
    [ ! -L "$d" ] || fail "$d is a symlink"
    [ -d "$d" ] || fail "$d is not a directory"
    [ "$(stat -f %u "$d")" = "$(id -u)" ] || fail "$d is not owned by you"
    mode="$(stat -f %Lp "$d")"
    [ $(( 8#$mode & 8#022 )) -eq 0 ] || fail "$d is writable by group or others (mode $mode)"
}

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

base="$HOME/Library/Caches/duo-updater"
cache="$base/xcodegen-$XCODEGEN_VERSION"
# Checked before anything is created inside: `mkdir -p` happily follows a symlink.
mkdir -p -m 700 "$base"
check_private_dir "$base"
mkdir -p -m 700 "$cache"
check_private_dir "$cache"

work="$(mktemp -d "$cache/work.XXXXXX")"
trap 'rm -rf "$work"' EXIT
zip="$work/xcodegen.zip"
cached="$cache/xcodegen.zip"

verified=0
if [ -f "$cached" ] && [ ! -L "$cached" ]; then
    cp "$cached" "$zip"
    if [ "$(sha256_of "$zip")" = "$XCODEGEN_SHA256" ]; then
        verified=1
    else
        note "cached zip does not match the pinned SHA-256 — discarding it"
    fi
elif [ -e "$cached" ] || [ -L "$cached" ]; then
    note "$cached is not a regular file — discarding it"
fi

if [ "$verified" -eq 0 ]; then
    rm -f "$cached"
    note "downloading XcodeGen $XCODEGEN_VERSION"
    curl -fsSL --retry 3 -o "$zip" "$URL" || fail "could not download $URL"
    got="$(sha256_of "$zip")"
    [ "$got" = "$XCODEGEN_SHA256" ] \
        || fail "downloaded zip fails the pinned SHA-256 (expected $XCODEGEN_SHA256, got $got)"
    cp "$zip" "$work/keep.zip" && mv -f "$work/keep.zip" "$cached"
fi

unzip -q "$zip" -d "$work/out" || fail "could not unpack the verified zip"
[ -x "$work/out/xcodegen/bin/xcodegen" ] || fail "the zip has no xcodegen/bin/xcodegen"
rm -rf "$cache/xcodegen"
mv "$work/out/xcodegen" "$cache/xcodegen"

printf '%s\n' "$cache/xcodegen/bin/xcodegen"

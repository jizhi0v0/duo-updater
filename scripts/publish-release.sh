#!/usr/bin/env bash
#
# Build, notarize, and publish a release into the public binary-only GitHub repo.
#
# Usage:
#   NOTARYTOOL_PROFILE=duoupdater-notary make release
#   TAG=v0.1.1 TITLE="DuoUpdater 0.1.1" NOTARYTOOL_PROFILE=duoupdater-notary scripts/publish-release.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$REPO_ROOT/App/project.yml"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
RELEASE_REPO="${RELEASE_REPO:-jizhi0v0/duo-updater-releases}"
FINAL_ZIP="${FINAL_ZIP:-$DIST_DIR/DuoUpdater-notarized.zip}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/duo-notary-dd}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
DRAFT_RELEASE="${DRAFT_RELEASE:-0}"
PRERELEASE="${PRERELEASE:-0}"
LATEST_RELEASE="${LATEST_RELEASE:-1}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ed25519}"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || die "gh not found"
command -v python3 >/dev/null || die "python3 not found"
command -v git >/dev/null || die "git not found"
command -v mktemp >/dev/null || die "mktemp not found"

gh repo view "$RELEASE_REPO" >/dev/null 2>&1 || die "release repo $RELEASE_REPO does not exist or is not accessible"
[ -f "$PROJECT_YML" ] || die "missing project file: $PROJECT_YML"

version="$(
python3 - <<'PY' "$PROJECT_YML"
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)" || die "failed to read MARKETING_VERSION from $PROJECT_YML"

build="$(
python3 - <<'PY' "$PROJECT_YML"
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)" || die "failed to read CURRENT_PROJECT_VERSION from $PROJECT_YML"

TAG="${TAG:-v$version}"
TITLE="${TITLE:-DuoUpdater $version}"
ASSET_ZIP="$DIST_DIR/DuoUpdater-$version-macos.zip"
AUTO_NOTES="$DIST_DIR/release-notes-$TAG.md"
DOWNLOAD_PREFIX="https://github.com/$RELEASE_REPO/releases/download/$TAG/"
RELEASE_PAGE_URL="https://github.com/$RELEASE_REPO/releases/tag/$TAG"

find_generate_appcast() {
    local candidate
    while IFS= read -r candidate; do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done < <(find "$DERIVED_DATA/SourcePackages" -path '*/Sparkle/bin/generate_appcast' -type f 2>/dev/null | sort)
    return 1
}

publish_sparkle_appcast() {
    local generate_appcast clone_dir archives_dir sparkle_notes release_repo_name

    generate_appcast="$(find_generate_appcast)" \
        || die "Sparkle generate_appcast not found under $DERIVED_DATA/SourcePackages. Re-run without SKIP_NOTARIZE so dependencies are built first."

    clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-updater-releases.XXXXXX")"
    archives_dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-updater-appcast.XXXXXX")"
    trap 'rm -rf "$clone_dir" "$archives_dir"' RETURN

    say "Cloning $RELEASE_REPO to update Sparkle appcast"
    gh repo clone "$RELEASE_REPO" "$clone_dir" >/dev/null

    cp "$ASSET_ZIP" "$archives_dir/"
    sparkle_notes="$archives_dir/$(basename "${ASSET_ZIP%.*}").md"
    cp "$RELEASE_NOTES_FILE" "$sparkle_notes"
    if [ -f "$clone_dir/appcast.xml" ]; then
        cp "$clone_dir/appcast.xml" "$archives_dir/appcast.xml"
        python3 - <<'PY' "$archives_dir/appcast.xml" "$build" "$version"
import pathlib
import re
import sys

path, build, version = sys.argv[1:4]
text = pathlib.Path(path).read_text()
pattern = re.compile(
    r"<item>.*?(?:<sparkle:version>\s*%s\s*</sparkle:version>|<sparkle:shortVersionString>\s*%s\s*</sparkle:shortVersionString>).*?</item>\s*"
    % (re.escape(build), re.escape(version)),
    re.S,
)
pathlib.Path(path).write_text(pattern.sub("", text))
PY
    fi

    say "Generating Sparkle appcast"
    "$generate_appcast" \
        --account "$SPARKLE_KEY_ACCOUNT" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --link "$RELEASE_PAGE_URL" \
        --embed-release-notes \
        "$archives_dir" >/dev/null

    cp "$archives_dir/appcast.xml" "$clone_dir/appcast.xml"

    release_repo_name="${RELEASE_REPO#*/}"
    if [ -d "$REPO_ROOT/../$release_repo_name/.git" ]; then
        cp "$archives_dir/appcast.xml" "$REPO_ROOT/../$release_repo_name/appcast.xml"
    fi

    if [ -n "$(git -C "$clone_dir" status --short -- appcast.xml)" ]; then
        say "Publishing Sparkle appcast to $RELEASE_REPO"
        git -C "$clone_dir" add appcast.xml
        git -C "$clone_dir" commit -m "Update Sparkle appcast for $TAG" >/dev/null
        git -C "$clone_dir" push origin HEAD >/dev/null
    else
        say "Sparkle appcast already up to date"
    fi
}

if [ "$SKIP_NOTARIZE" != "1" ]; then
    say "Building and notarizing release artifact"
    "$REPO_ROOT/scripts/notarize.sh"
fi

[ -f "$FINAL_ZIP" ] || die "notarized zip not found: $FINAL_ZIP"
mkdir -p "$DIST_DIR"
cp "$FINAL_ZIP" "$ASSET_ZIP"

checksum="$(shasum -a 256 "$ASSET_ZIP" | awk '{print $1}')"

if [ -z "$RELEASE_NOTES_FILE" ]; then
    RELEASE_NOTES_FILE="$AUTO_NOTES"
    # Prefer this version's section from CHANGELOG.md (the user-facing source of
    # truth). Extract the body under "## <version>" up to the next "## " heading.
    # Only fall back to the boilerplate when there's no such section, so a release
    # never silently ships metadata-only notes when real notes exist.
    changelog_section="$(
        CHANGELOG="$REPO_ROOT/CHANGELOG.md" VERSION="$version" python3 - <<'PY'
import os, re, sys
path = os.environ["CHANGELOG"]
version = os.environ["VERSION"]
try:
    text = open(path, encoding="utf-8").read()
except OSError:
    sys.exit(0)
# Match a "## <version>" heading (tolerating "## [1.2.3]" or "## 1.2.3 — date"),
# capturing everything up to the next top-level "## " heading.
pat = re.compile(
    r'^##\s*\[?' + re.escape(version) + r'\]?\b.*?\n(.*?)(?=^##\s|\Z)',
    re.MULTILINE | re.DOTALL)
m = pat.search(text)
if m:
    body = m.group(1).strip()
    if body:
        print(body)
PY
    )"
    if [ -n "$changelog_section" ]; then
        printf '%s\n' "$changelog_section" > "$RELEASE_NOTES_FILE"
        say "Release notes: using CHANGELOG.md section for $version"
    else
        say "Release notes: no CHANGELOG.md section for $version — using generated metadata"
        cat > "$RELEASE_NOTES_FILE" <<EOF
## DuoUpdater $version

- Released: $(date +%F)
- Build: $build
- Package: notarized macOS app bundle
- Install: download \`$(basename "$ASSET_ZIP")\`, unzip it, move \`DuoUpdater.app\` to \`/Applications\`, then open it once.

SHA-256: \`$checksum\`
EOF
    fi
fi

[ -f "$RELEASE_NOTES_FILE" ] || die "release notes file not found: $RELEASE_NOTES_FILE"

release_exists=0
if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    release_exists=1
fi

extra_flags=()
[ "$DRAFT_RELEASE" = "1" ] && extra_flags+=(--draft)
[ "$PRERELEASE" = "1" ] && extra_flags+=(--prerelease)
[ "$LATEST_RELEASE" = "1" ] && extra_flags+=(--latest)

if [ "$release_exists" = "1" ]; then
    say "Updating existing release $TAG in $RELEASE_REPO"
    gh release edit "$TAG" \
        --repo "$RELEASE_REPO" \
        --title "$TITLE" \
        --notes-file "$RELEASE_NOTES_FILE"
    gh release upload "$TAG" "$ASSET_ZIP" \
        --repo "$RELEASE_REPO" \
        --clobber
else
    say "Creating release $TAG in $RELEASE_REPO"
    gh release create "$TAG" "$ASSET_ZIP" \
        --repo "$RELEASE_REPO" \
        --title "$TITLE" \
        --notes-file "$RELEASE_NOTES_FILE" \
        "${extra_flags[@]}"
fi

publish_sparkle_appcast

cat <<EOF

$(printf '\033[1;32m✓ Published successfully.\033[0m')
   repo     : $RELEASE_REPO
   tag      : $TAG
   title    : $TITLE
   asset    : $ASSET_ZIP
   appcast  : https://raw.githubusercontent.com/$RELEASE_REPO/main/appcast.xml
   notes    : $RELEASE_NOTES_FILE
   sha256   : $checksum
EOF

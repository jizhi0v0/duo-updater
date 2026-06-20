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
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
DRAFT_RELEASE="${DRAFT_RELEASE:-0}"
PRERELEASE="${PRERELEASE:-0}"
LATEST_RELEASE="${LATEST_RELEASE:-1}"

say() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || die "gh not found"
command -v python3 >/dev/null || die "python3 not found"

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
    cat > "$RELEASE_NOTES_FILE" <<EOF
## DuoUpdater $version

- Released: $(date +%F)
- Build: $build
- Package: notarized macOS app bundle
- Install: download \`$(basename "$ASSET_ZIP")\`, unzip it, move \`DuoUpdater.app\` to \`/Applications\`, then open it once.

SHA-256: \`$checksum\`
EOF
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

cat <<EOF

$(printf '\033[1;32m✓ Published successfully.\033[0m')
   repo     : $RELEASE_REPO
   tag      : $TAG
   title    : $TITLE
   asset    : $ASSET_ZIP
   notes    : $RELEASE_NOTES_FILE
   sha256   : $checksum
EOF

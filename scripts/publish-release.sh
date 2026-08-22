#!/usr/bin/env bash
#
# Build, notarize, and publish a GitHub Release, and update the Sparkle appcast
# the app updates itself from.
#
# Both live in this repository. They used to live in a separate binary-only repo,
# which existed only because the source was private; RELEASE_REPO still overrides
# the target if you want them somewhere else.
#
# Usage:
#   NOTARYTOOL_PROFILE=duoupdater-notary make release
#   TAG=v0.1.1 TITLE="DuoUpdater 0.1.1" NOTARYTOOL_PROFILE=duoupdater-notary scripts/publish-release.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$REPO_ROOT/App/project.yml"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
RELEASE_REPO="${RELEASE_REPO:-jizhi0v0/duo-updater}"
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
    local generate_appcast clone_dir archives_dir sparkle_notes setting value

    generate_appcast="$(find_generate_appcast)" \
        || die "Sparkle generate_appcast not found under $DERIVED_DATA/SourcePackages. Re-run without SKIP_NOTARIZE so dependencies are built first."

    clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-updater-appcast-clone.XXXXXX")"
    archives_dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-updater-appcast.XXXXXX")"
    trap 'rm -rf "$clone_dir" "$archives_dir"' RETURN

    # A throwaway shallow clone, even though this is now the same repository the
    # script is running from. Committing the appcast into the working tree would
    # mean the release touches whatever branch happens to be checked out and
    # whatever is uncommitted beside it; a clone keeps publishing independent of
    # the state of your checkout.
    say "Cloning $RELEASE_REPO to update Sparkle appcast"
    gh repo clone "$RELEASE_REPO" "$clone_dir" -- --depth 1 >/dev/null

    # Carry this repo's commit identity into the clone. A fresh clone otherwise
    # falls back to the global config, which is how the 0.3.18 appcast push was
    # rejected by GitHub's "block pushes that expose my email" setting while the
    # release itself had already gone out: the working repo used a noreply
    # address, the throwaway clone did not.
    for setting in user.name user.email; do
        value="$(git -C "$REPO_ROOT" config --get "$setting" || true)"
        [ -n "$value" ] && git -C "$clone_dir" config "$setting" "$value"
    done

    cp "$ASSET_ZIP" "$archives_dir/"
    sparkle_notes="$archives_dir/$(basename "${ASSET_ZIP%.*}").md"
    cp "$RELEASE_NOTES_FILE" "$sparkle_notes"
    if [ -f "$clone_dir/appcast.xml" ]; then
        cp "$clone_dir/appcast.xml" "$archives_dir/appcast.xml"
        python3 - <<'PY' "$archives_dir/appcast.xml" "$build" "$version"
import pathlib
import re
import sys

# Drop the item for the version being published, so generate_appcast writes a
# fresh one rather than a duplicate.
#
# Split into whole items FIRST. The obvious single regex --
# <item>.*?(<sparkle:version>BUILD</sparkle:version>|...).*?</item> with DOTALL --
# is wrong in a way that only shows up when you republish something that is not
# the newest entry: the lazy prefix starts at the FIRST <item> in the file and
# swallows every item before the match. Republishing the newest costs one extra
# entry, which is how 0.3.50 vanished from the feed on 2026-08-22; republishing
# an older one empties the appcast completely. Verified against a three-item
# feed: re-running the old form for the oldest build deleted all three.
path, build, version = sys.argv[1:4]
text = pathlib.Path(path).read_text()

item = re.compile(r"<item>.*?</item>\s*", re.S)
target = re.compile(
    r"<sparkle:version>\s*%s\s*</sparkle:version>"
    r"|<sparkle:shortVersionString>\s*%s\s*</sparkle:shortVersionString>"
    % (re.escape(build), re.escape(version))
)
pathlib.Path(path).write_text(
    item.sub(lambda m: "" if target.search(m.group()) else m.group(), text))
PY
    fi

    say "Generating Sparkle appcast"
    "$generate_appcast" \
        --account "$SPARKLE_KEY_ACCOUNT" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --link "$RELEASE_PAGE_URL" \
        --embed-release-notes \
        "$archives_dir" >/dev/null

    # Nothing may vanish from the feed. At this point `$clone_dir/appcast.xml` is
    # still the published copy and `$archives_dir/appcast.xml` is the regenerated
    # one, so they can simply be counted against each other. A shrinking feed is
    # how the strip step used to fail silently — and a lost entry is not cosmetic:
    # it is a version nobody can be offered any more.
    OLD_APPCAST="$clone_dir/appcast.xml" NEW_APPCAST="$archives_dir/appcast.xml" \
        NEW_VERSION="$version" python3 - <<'PY' || die "appcast sanity check failed"
import os, pathlib, re, sys

def versions(path):
    text = pathlib.Path(path).read_text()
    return re.findall(r"<sparkle:shortVersionString>\s*([^<\s]+)\s*</sparkle:shortVersionString>", text)

old = versions(os.environ["OLD_APPCAST"])
new = versions(os.environ["NEW_APPCAST"])
want = os.environ["NEW_VERSION"]

if want not in new:
    sys.exit(f"the regenerated appcast does not contain {want} — it would publish nothing")

# generate_appcast keeps a rolling window, so the OLDEST entries legitimately
# roll off the end: this feed has held three for as long as it has existed.
# What is never legitimate is an entry disappearing from the front or the
# middle, which is precisely how the old strip regex failed — its lazy prefix
# began at the first <item> in the file and swallowed everything before the one
# it was aiming at. So the test is not "did the count fall" (it does not, when
# one rolls off as one is added, which is why counting alone waved through the
# loss of 0.3.49) but "is what vanished a suffix of what we had".
# A rolling window sheds at most one entry per publish, so more than one going
# missing is not the window — it is the bug. (Written after the suffix rule
# alone waved through a feed emptied down to the new entry: everything lost is
# trivially a suffix of everything.)
lost = [v for v in old if v not in new]
if len(lost) > 1:
    sys.exit(
        f"the regenerated appcast lost {len(lost)} entries: {', '.join(lost)}\n"
        f"  before: {', '.join(old)}\n  after:  {', '.join(new)}"
    )
if lost:
    tail = old[len(old) - len(lost):]
    if lost != tail:
        sys.exit(
            f"the regenerated appcast lost {', '.join(lost)} from the middle of the feed\n"
            f"  before: {', '.join(old)}\n  after:  {', '.join(new)}"
        )
    print(f"  appcast: {', '.join(lost)} rolled off the end, {want} added")
print(f"  appcast: {len(old)} -> {len(new)} entries, {want} present")
PY

    cp "$archives_dir/appcast.xml" "$clone_dir/appcast.xml"

    if [ -n "$(git -C "$clone_dir" status --short -- appcast.xml)" ]; then
        say "Publishing Sparkle appcast to $RELEASE_REPO"
        git -C "$clone_dir" add appcast.xml
        git -C "$clone_dir" commit -m "Update Sparkle appcast for $TAG" >/dev/null
        git -C "$clone_dir" push origin HEAD >/dev/null
    else
        say "Sparkle appcast already up to date"
    fi
}

# Refuse to publish a build the updater cannot see as new.
#
# Sparkle decides "is this newer" from CFBundleVersion (sparkle:version), not
# from the version name. 0.3.51 shipped with CURRENT_PROJECT_VERSION left at the
# previous release's value, so every user already on 0.3.50 was told they were
# up to date and never offered it; 0.3.52 exists only to correct that. Nothing
# in this script noticed. It does now, before anything is built.
#
# Read the live appcast from git rather than the raw.githubusercontent URL: that
# CDN lags several minutes and no cache-buster gets through it, so it is exactly
# blind to the failure "the last push did not land".
preflight_build_is_newer() {
    local published
    git -C "$REPO_ROOT" fetch origin main --quiet 2>/dev/null || true
    published="$(git -C "$REPO_ROOT" show origin/main:appcast.xml 2>/dev/null || true)"
    [ -n "$published" ] || { say "No published appcast yet — skipping the build-number check"; return 0; }

    APPCAST_XML="$published" NEW_BUILD="$build" python3 - <<'PY' || die "build number check failed"
import os, re, sys
xml = os.environ["APPCAST_XML"]
new = os.environ["NEW_BUILD"]
builds = [int(b) for b in re.findall(r"<sparkle:version>\s*(\d+)\s*</sparkle:version>", xml)]
if not builds:
    print("  no sparkle:version entries in the published appcast — nothing to compare")
    sys.exit(0)
try:
    mine = int(new)
except ValueError:
    sys.exit(f"CURRENT_PROJECT_VERSION {new!r} is not a number; Sparkle compares it numerically")
top = max(builds)
if mine <= top:
    sys.exit(
        f"CURRENT_PROJECT_VERSION is {mine}, but the published appcast already has {top}.\n"
        f"  Sparkle compares CFBundleVersion, so every user on build {top} would be told\n"
        f"  they are up to date and never offered this release. Bump\n"
        f"  CURRENT_PROJECT_VERSION in App/project.yml (both occurrences)."
    )
print(f"  build {mine} > published {top}")
PY
}

say "Checking the build number against the published appcast"
preflight_build_is_newer

# The tests are the only gate this project has — there is no CI on pull
# requests — and until now `make release` did not run them, so a release could
# go out over a red suite without anyone being asked.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
    say "Running tests before publishing (SKIP_TESTS=1 to override)"
    ( cd "$REPO_ROOT/DuoUpdaterCore" && swift test ) >/dev/null 2>&1 \
        || die "swift test failed — refusing to publish. Run 'make test' to see it."
fi

if [ "$SKIP_NOTARIZE" != "1" ]; then
    say "Building and notarizing release artifact"
    "$REPO_ROOT/scripts/notarize.sh"
fi

[ -f "$FINAL_ZIP" ] || die "notarized zip not found: $FINAL_ZIP"
mkdir -p "$DIST_DIR"
cp "$FINAL_ZIP" "$ASSET_ZIP"

# The zip must contain the versions we are about to tag. With SKIP_NOTARIZE=1
# this script reuses whatever `dist/DuoUpdater-notarized.zip` is lying around,
# which can be the previous build — a silent path to "the tag says A, the
# binary is B".
say "Checking the artifact's own version"
zip_info="$(unzip -Z1 "$ASSET_ZIP" | grep -m1 -E '^[^/]+\.app/Contents/Info\.plist$' || true)"
[ -n "$zip_info" ] || die "no app Info.plist inside $ASSET_ZIP"
zip_short="$(unzip -p "$ASSET_ZIP" "$zip_info" | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || true)"
zip_build="$(unzip -p "$ASSET_ZIP" "$zip_info" | plutil -extract CFBundleVersion raw - 2>/dev/null || true)"
[ "$zip_short" = "$version" ] \
    || die "artifact is version $zip_short but this release is $version — stale zip? (rebuild, or unset SKIP_NOTARIZE)"
[ "$zip_build" = "$build" ] \
    || die "artifact is build $zip_build but this release is build $build — stale zip? (rebuild, or unset SKIP_NOTARIZE)"

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

# The GitHub release page is where someone downloads DuoUpdater for the FIRST
# time, so it's the one place that has to state what it runs on: an Intel Mac
# would otherwise download, unzip, and get "cannot be opened" with no
# explanation. Appended into a separate file rather than onto $RELEASE_NOTES_FILE
# — that same file becomes the Sparkle release notes shown inside the app, where
# a requirements line is pure noise (anyone reading it is already running us on
# a supported Mac). Keeping the two bodies distinct also means a hand-supplied
# --notes-file is never modified on disk.
GITHUB_NOTES_FILE="$DIST_DIR/release-notes-$TAG-github.md"
{
    cat "$RELEASE_NOTES_FILE"
    cat <<'EOF'

---

**Requires macOS 14 or later on an Apple Silicon Mac.** Intel Macs are not supported.
EOF
} > "$GITHUB_NOTES_FILE"

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
        --notes-file "$GITHUB_NOTES_FILE"
    gh release upload "$TAG" "$ASSET_ZIP" \
        --repo "$RELEASE_REPO" \
        --clobber
else
    say "Creating release $TAG in $RELEASE_REPO"
    gh release create "$TAG" "$ASSET_ZIP" \
        --repo "$RELEASE_REPO" \
        --title "$TITLE" \
        --notes-file "$GITHUB_NOTES_FILE" \
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
   notes    : $RELEASE_NOTES_FILE (in-app) / $GITHUB_NOTES_FILE (release page)
   sha256   : $checksum
EOF

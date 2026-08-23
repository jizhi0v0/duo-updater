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

# Both keys appear once per target in project.yml, and the whole release turns
# on the build number, so a half-done bump must not be readable as a decision.
# `re.search` took the first match and said nothing: bump only the second
# occurrence and the build check below compares the STALE number against the
# feed and refuses; bump only the first and it passes on a number the app may
# not carry (the zip check later is the only thing that catches that).
read_project_setting() {
    PROJECT_YML="$PROJECT_YML" SETTING="$1" python3 - <<'PY'
import os, pathlib, re, sys
text = pathlib.Path(os.environ["PROJECT_YML"]).read_text()
setting = os.environ["SETTING"]
found = re.findall(r'%s:\s*"([^"]+)"' % re.escape(setting), text)
if not found:
    sys.exit(f"no {setting} in the project file")
if len(set(found)) != 1:
    sys.exit(
        f"{setting} disagrees with itself: {', '.join(found)}\n"
        f"  All occurrences must be bumped together.")
print(found[0])
PY
}

version="$(read_project_setting MARKETING_VERSION)" \
    || die "failed to read MARKETING_VERSION from $PROJECT_YML"
build="$(read_project_setting CURRENT_PROJECT_VERSION)" \
    || die "failed to read CURRENT_PROJECT_VERSION from $PROJECT_YML"

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

# Maximum entries the feed keeps, per branch point.
#
# Passed explicitly because the check below has to know exactly when an entry
# rolling off the end is legitimate, and a cap inferred from "how many there
# happen to be" is not a cap, it is a guess. Note this is a real change, not a
# restatement: `generate_appcast --help` gives the default as 3, which is why the
# published feed has held three items. Five keeps a little more history.
APPCAST_MAX_VERSIONS=5

# Scratch directories for the appcast work. Deliberately file-scope, and cleaned
# on EXIT rather than RETURN: the appcast is now prepared in one function and
# pushed by another, and `die` exits the process without ever unwinding a RETURN
# trap — so a failed check used to leak exactly the directories you want to open.
appcast_clone_dir=""
appcast_archives_dir=""
cleanup_appcast_dirs() {
    local rc=$?
    if [ "$rc" != "0" ] && [ -n "$appcast_clone_dir" ]; then
        printf '  left for inspection: %s %s\n' "$appcast_clone_dir" "$appcast_archives_dir" >&2
        return
    fi
    [ -n "$appcast_clone_dir" ] && rm -rf "$appcast_clone_dir"
    [ -n "$appcast_archives_dir" ] && rm -rf "$appcast_archives_dir"
    return 0
}
trap cleanup_appcast_dirs EXIT

# Build the new appcast and check it, WITHOUT publishing anything.
#
# Called before the GitHub Release is created. It used to run after, so every
# way this can refuse — and it has several — left a live release with no feed
# entry behind it. Nothing here touches the outside world: the clone is
# throwaway and the push is `push_sparkle_appcast`'s job.
prepare_sparkle_appcast() {
    local generate_appcast sparkle_notes setting value

    generate_appcast="$(find_generate_appcast)" \
        || die "Sparkle generate_appcast not found under $DERIVED_DATA/SourcePackages. Re-run without SKIP_NOTARIZE so dependencies are built first."

    appcast_clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-updater-appcast-clone.XXXXXX")"
    appcast_archives_dir="$(mktemp -d "${TMPDIR:-/tmp}/duo-updater-appcast.XXXXXX")"

    # A throwaway shallow clone, even though this is now the same repository the
    # script is running from. Committing the appcast into the working tree would
    # mean the release touches whatever branch happens to be checked out and
    # whatever is uncommitted beside it; a clone keeps publishing independent of
    # the state of your checkout.
    say "Cloning $RELEASE_REPO to update Sparkle appcast"
    gh repo clone "$RELEASE_REPO" "$appcast_clone_dir" -- --depth 1 >/dev/null

    # Carry this repo's commit identity into the clone. A fresh clone otherwise
    # falls back to the global config, which is how the 0.3.18 appcast push was
    # rejected by GitHub's "block pushes that expose my email" setting while the
    # release itself had already gone out: the working repo used a noreply
    # address, the throwaway clone did not.
    for setting in user.name user.email; do
        value="$(git -C "$REPO_ROOT" config --get "$setting" || true)"
        [ -n "$value" ] && git -C "$appcast_clone_dir" config "$setting" "$value"
    done

    cp "$ASSET_ZIP" "$appcast_archives_dir/"
    sparkle_notes="$appcast_archives_dir/$(basename "${ASSET_ZIP%.*}").md"
    cp "$RELEASE_NOTES_FILE" "$sparkle_notes"
    if [ -f "$appcast_clone_dir/appcast.xml" ]; then
        cp "$appcast_clone_dir/appcast.xml" "$appcast_archives_dir/appcast.xml"
        REPO_ROOT="$REPO_ROOT" APPCAST="$appcast_archives_dir/appcast.xml" \
            BUILD="$build" VERSION="$version" \
            python3 - <<'PY' || die "could not prepare the published appcast for regeneration"
import os, pathlib, sys
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "scripts"))
import appcast_edit

path = pathlib.Path(os.environ["APPCAST"])
text = path.read_text()

# `strip_item` runs over the whole document while `generate_appcast` regenerates
# a single channel, so on a multi-channel feed it would delete the other
# channel's entry with nothing to put back. There has never been a second
# channel here; if one appears, stop rather than guess at scoping.
channels = appcast_edit.channel_count(text)
if channels > 1:
    sys.exit(
        f"the published appcast has {channels} channels — this script only handles one.\n"
        "  Scope the item strip to a channel before publishing again.")

path.write_text(appcast_edit.strip_item(text, os.environ["BUILD"], os.environ["VERSION"]))
PY
    fi

    say "Generating Sparkle appcast"
    "$generate_appcast" \
        --account "$SPARKLE_KEY_ACCOUNT" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --link "$RELEASE_PAGE_URL" \
        --maximum-versions "$APPCAST_MAX_VERSIONS" \
        --embed-release-notes \
        "$appcast_archives_dir" >/dev/null

    # What the regenerated feed has to look like. `$appcast_clone_dir/appcast.xml`
    # is still the published copy and `$appcast_archives_dir/appcast.xml` is the
    # new one, so they can be compared directly.
    #
    # The rule is an exact entry count, not "did anything vanish". Counting
    # losses alone waved through 0.3.49 (one rolls off as one is added, so the
    # count holds), and "at most one lost and it must be the oldest" is trivially
    # true of a one-entry feed that lost its only entry. Knowing the cap makes it
    # exact: the new feed holds everything the old one had plus this version,
    # clipped to the window, and nothing else is acceptable.
    OLD_APPCAST="$appcast_clone_dir/appcast.xml" NEW_APPCAST="$appcast_archives_dir/appcast.xml" \
        NEW_VERSION="$version" NEW_BUILD="$build" ASSET_ZIP="$ASSET_ZIP" \
        MAX_VERSIONS="$APPCAST_MAX_VERSIONS" REPO_ROOT="$REPO_ROOT" \
        python3 - <<'PY' || die "appcast sanity check failed"
import os, pathlib, sys
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "scripts"))
import appcast_edit

new_text = pathlib.Path(os.environ["NEW_APPCAST"]).read_text()
# A first publish into a fresh release repo has no published appcast to compare
# against. Treated as an empty feed rather than crashed on — this used to raise
# FileNotFoundError and report it as "appcast sanity check failed", after the
# release had already been created.
old_path = pathlib.Path(os.environ["OLD_APPCAST"])
old_text = old_path.read_text() if old_path.exists() else ""
size = pathlib.Path(os.environ["ASSET_ZIP"]).stat().st_size

problems = appcast_edit.check_regenerated(
    old_text, new_text, os.environ["NEW_VERSION"], os.environ["NEW_BUILD"],
    size, int(os.environ["MAX_VERSIONS"]))
old = appcast_edit.short_versions(old_text)
new = appcast_edit.short_versions(new_text)
if problems:
    sys.exit("\n".join(problems)
             + f"\n  before: {', '.join(old) or '(empty)'}"
             + f"\n  after:  {', '.join(new) or '(empty)'}")

lost = [v for v in old if v not in new]
if lost:
    print(f"  appcast: {', '.join(lost)} rolled off the end of a {os.environ['MAX_VERSIONS']}-entry window")
print(f"  appcast: {len(old)} -> {len(new)} entries, {os.environ['NEW_VERSION']} present, enclosure {size} bytes")
PY
}

# Commit and push the appcast prepared above. Split from the preparation so
# every check runs before the release exists.
push_sparkle_appcast() {
    cp "$appcast_archives_dir/appcast.xml" "$appcast_clone_dir/appcast.xml"

    if [ -n "$(git -C "$appcast_clone_dir" status --short -- appcast.xml)" ]; then
        say "Publishing Sparkle appcast to $RELEASE_REPO"
        git -C "$appcast_clone_dir" add appcast.xml
        git -C "$appcast_clone_dir" commit -m "Update Sparkle appcast for $TAG" >/dev/null
        # The clone is taken before the release is created and the asset uploaded,
        # so minutes pass before this runs and another push can land in between.
        # (When this all lived in one function the window was too small to matter.)
        local attempt
        for attempt in 1 2 3; do
            if git -C "$appcast_clone_dir" push origin HEAD >/dev/null 2>&1; then
                return 0
            fi
            say "  appcast push rejected (attempt $attempt) — rebasing onto the current head"
            git -C "$appcast_clone_dir" fetch origin --quiet 2>/dev/null || true
            git -C "$appcast_clone_dir" pull --rebase --quiet origin HEAD 2>/dev/null || true
        done
        die "the GitHub Release for $TAG IS LIVE, but the Sparkle appcast could NOT be pushed.
  Users will not be offered it until the feed is updated. Re-run this script — the
  release will be updated in place and the appcast retried."
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
    if [ "${SKIP_BUILD_CHECK:-0}" = "1" ]; then
        say "SKIP_BUILD_CHECK=1 — NOT checking that this build is newer than the published one."
        say "  Users already on the published build will not be offered this release."
        return 0
    fi
    # Every failure below is fatal, and that is the whole point. "I could not read
    # the published appcast" and "there is no published appcast" are different
    # facts, and the old code reported both as the second and carried on. The
    # appcast is pushed from a throwaway clone, so this checkout's `origin/main`
    # only learns the last release through this fetch: swallow a failed fetch and
    # the baseline silently rewinds to the release before last, which is enough to
    # wave through the exact omission this check exists for. SKIP_BUILD_CHECK=1 is
    # the way past it — loudly, and on purpose.
    git -C "$REPO_ROOT" fetch origin main --quiet \
        || die "could not fetch origin/main, so the published build number is unknown.
  Publishing on a stale baseline is how 0.3.51 shipped unreachable. Fix the
  network, or SKIP_BUILD_CHECK=1 if you have checked the feed by hand."
    git -C "$REPO_ROOT" rev-parse --verify --quiet origin/main >/dev/null \
        || die "no origin/main in this checkout, so the published appcast cannot be read.
  SKIP_BUILD_CHECK=1 to publish anyway."
    if ! published="$(git -C "$REPO_ROOT" show origin/main:appcast.xml 2>/dev/null)"; then
        # The ref resolves but carries no appcast: a genuine first publish.
        say "No appcast on origin/main yet — first publish, nothing to compare"
        return 0
    fi

    APPCAST_XML="$published" NEW_BUILD="$build" python3 - <<'PY' || die "build number check failed"
import os, re, sys
xml = os.environ["APPCAST_XML"]
new = os.environ["NEW_BUILD"]
builds = [int(b) for b in re.findall(r"<sparkle:version>\s*(\d+)\s*</sparkle:version>", xml)]
if not builds:
    # An empty feed is the documented starting state and is fine. A feed with
    # items but no readable build number is not: Sparkle also permits
    # `sparkle:version` as an enclosure attribute, and a format change that this
    # pattern cannot read must not be reported as "nothing to compare".
    if "<item" in xml:
        sys.exit(
            "the published appcast has items but no <sparkle:version> element.\n"
            "  The format changed and this check can no longer read it — fix the\n"
            "  pattern rather than publishing blind (SKIP_BUILD_CHECK=1 to override).")
    print("  the published appcast is empty — nothing to compare")
    sys.exit(0)
try:
    mine = int(new)
except ValueError:
    sys.exit(f"CURRENT_PROJECT_VERSION {new!r} is not a number; Sparkle compares it numerically")
top = max(builds)
# Re-running a publish for a version that is already the newest entry is a
# supported operation — `gh release edit`/`upload --clobber` on this side, and
# `strip_item` plus an unchanged feed on the other. Only the exact same build
# qualifies: anything lower really is unreachable for users on `top`.
if mine == top and os.environ.get("REISSUE") == "1":
    print(f"  REISSUE=1 — republishing build {mine}, already the newest published entry")
    sys.exit(0)
if mine <= top:
    sys.exit(
        f"CURRENT_PROJECT_VERSION is {mine}, but the published appcast already has {top}.\n"
        f"  Sparkle compares CFBundleVersion, so every user on build {top} would be told\n"
        f"  they are up to date and never offered this release. Bump\n"
        f"  CURRENT_PROJECT_VERSION in App/project.yml (both occurrences).\n"
        f"  If you meant to re-publish build {top} rather than ship a new one, REISSUE=1."
    )
print(f"  build {mine} > published {top}")
PY
}

# The commit the artifact is built from, and the one the tag will point at.
# Nothing else in this script tied the two together: the zip comes from the
# working tree, the tag came from whatever the remote default branch happened to
# be. A dirty tree means the zip contains code that is in no commit at all, so
# the tag cannot be honest about it either way.
RELEASE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    if [ "${ALLOW_DIRTY_TREE:-0}" = "1" ]; then
        say "ALLOW_DIRTY_TREE=1 — publishing from a dirty tree; the tag will NOT match the artifact."
    else
        die "the working tree has uncommitted changes, so tag $TAG would not describe
  what is in the artifact. Commit them, or ALLOW_DIRTY_TREE=1 to publish anyway."
    fi
fi

# Whether the tag may be pinned to this commit at all.
#
# Only when the release is going to the repository this commit lives in. The
# documented RELEASE_REPO override points somewhere else, where a SHA from here
# means nothing — GitHub answers 422 invalid target_commitish — so pinning would
# quietly kill an escape hatch the header advertises. There, fall back to gh's
# default (the remote's own default branch), which is what it always did.
RELEASE_TARGET_FLAG=""
origin_slug="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null \
    | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##; s#^https://github\.com/##' || true)"
if [ "$origin_slug" = "$RELEASE_REPO" ]; then
    RELEASE_TARGET_FLAG=1
else
    say "RELEASE_REPO ($RELEASE_REPO) is not this checkout's origin ($origin_slug)"
    say "  — the tag will be created from that repo's default branch, not $RELEASE_COMMIT"
fi

# HEAD being committed is not the same as GitHub having it. An unpushed HEAD
# answers 422 invalid target_commitish — cleanly, but only after build, notarize
# and appcast preparation have run, i.e. tens of minutes in, as a raw API blob.
if [ -n "$RELEASE_TARGET_FLAG" ]; then
    git -C "$REPO_ROOT" fetch origin --quiet 2>/dev/null || true
    if [ -z "$(git -C "$REPO_ROOT" branch -r --contains "$RELEASE_COMMIT" 2>/dev/null)" ]; then
        if [ "${ALLOW_UNPUSHED:-0}" = "1" ]; then
            say "ALLOW_UNPUSHED=1 — $RELEASE_COMMIT is on no remote branch;"
            say "  the tag will be created from the default branch, which does NOT contain this build."
            RELEASE_TARGET_FLAG=""
        else
            die "$RELEASE_COMMIT is on no remote branch, so GitHub cannot tag it.
  Push the branch first, or ALLOW_UNPUSHED=1 to let gh tag the default branch instead."
        fi
    fi
fi

say "Checking the build number against the published appcast"
preflight_build_is_newer

# The tests are the only gate this project has — there is no CI on pull
# requests — and until now `make release` did not run them, so a release could
# go out over a red suite without anyone being asked.
# Not under SKIP_TESTS: these cover the appcast surgery this script is about to
# perform, they need no network, and they finish in milliseconds.
say "Checking the appcast editing rules"
python3 "$REPO_ROOT/scripts/test_appcast_edit.py" \
    || die "the appcast edit tests failed — refusing to publish."

if [ "${SKIP_TESTS:-0}" = "1" ]; then
    say "SKIP_TESTS=1 — NOT running the test suite before publishing."
else
    say "Running tests before publishing (SKIP_TESTS=1 to override)"
    # `make test`, not one package: this ran only DuoUpdaterCore, so a red CLI
    # suite published. Output is NOT swallowed — some of these tests hit the
    # network, and swallowing makes "the network blipped" and "the suite is red"
    # the same silence.
    ( cd "$REPO_ROOT" && make test ) || die "tests failed — refusing to publish."
fi

if [ "$SKIP_NOTARIZE" = "1" ]; then
    say "SKIP_NOTARIZE=1 — NOT rebuilding; reusing $FINAL_ZIP as it stands."
    say "  (its version is checked below, but nothing else about it is.)"
else
    say "Building and notarizing release artifact"
    "$REPO_ROOT/scripts/notarize.sh"
fi

[ -f "$FINAL_ZIP" ] || die "notarized zip not found: $FINAL_ZIP"
mkdir -p "$DIST_DIR"

# The zip must contain the versions we are about to tag. With SKIP_NOTARIZE=1
# this script reuses whatever `dist/DuoUpdater-notarized.zip` is lying around,
# which can be the previous build — a silent path to "the tag says A, the
# binary is B".
# Checked before it is copied to this version's name. Copying first left a
# rejected stale zip sitting in dist/ renamed to the version it is NOT — a trap
# for the next SKIP_NOTARIZE=1 run, which reuses whatever is lying around.
say "Checking the artifact's own version"
zip_info="$(unzip -Z1 "$FINAL_ZIP" | grep -m1 -E '^[^/]+\.app/Contents/Info\.plist$' || true)"
[ -n "$zip_info" ] || die "no app Info.plist inside $FINAL_ZIP"
zip_short="$(unzip -p "$FINAL_ZIP" "$zip_info" | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || true)"
zip_build="$(unzip -p "$FINAL_ZIP" "$zip_info" | plutil -extract CFBundleVersion raw - 2>/dev/null || true)"
[ "$zip_short" = "$version" ] \
    || die "artifact is version $zip_short but this release is $version — stale zip? (rebuild, or unset SKIP_NOTARIZE)"
[ "$zip_build" = "$build" ] \
    || die "artifact is build $zip_build but this release is build $build — stale zip? (rebuild, or unset SKIP_NOTARIZE)"

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

# A draft or prerelease is deliberately not for everyone, but the appcast is:
# every installed copy reads it. Pushing a feed entry for a draft points Sparkle
# at a download URL that 404s for anyone who is not the author, on every check.
# Whether the release will be visible to users, read from GITHUB rather than
# from this run's env vars — those describe what THIS invocation asked for, and
# the release may already be something else.
#
# Two ways that bites. `gh release edit` is never given --draft=false, so a
# release created with DRAFT_RELEASE=1 stays a draft when a later run "publishes"
# it — and that later run, with the flag unset, would push a feed pointing at a
# draft's download URL, which 404s for everyone but the author. And `gh release
# create` with an asset creates a draft, uploads, then publishes, so an
# interrupted upload leaves a draft behind that the next run adopts.
is_draft=0
is_prerelease=0
if [ "$release_exists" = "1" ]; then
    is_draft="$(gh release view "$TAG" --repo "$RELEASE_REPO" --json isDraft \
        --jq 'if .isDraft then 1 else 0 end' 2>/dev/null || echo 1)"
    is_prerelease="$(gh release view "$TAG" --repo "$RELEASE_REPO" --json isPrerelease \
        --jq 'if .isPrerelease then 1 else 0 end' 2>/dev/null || echo 1)"
fi
[ "$DRAFT_RELEASE" = "1" ] && is_draft=1
[ "$PRERELEASE" = "1" ] && is_prerelease=1

publishes_appcast=1
if [ "$is_draft" = "1" ] || [ "$is_prerelease" = "1" ]; then
    publishes_appcast=0
fi

# Build and check the feed BEFORE the release exists, so a refusal here does not
# leave a published release with nothing pointing at it.
if [ "$publishes_appcast" = "1" ]; then
    prepare_sparkle_appcast
else
    say "Draft/prerelease — the Sparkle appcast will NOT be updated"
    say "  (a draft's download URL is not reachable by users; the feed stays as it is)"
fi

# GitHub refuses --latest on a draft or a prerelease ("Drafts and prereleases
# cannot be set as latest"), and LATEST_RELEASE defaults to 1, so passing it
# unconditionally meant relying on that refusal being silent.
release_flags=()
[ "$is_draft" = "1" ] && release_flags+=(--draft)
[ "$is_prerelease" = "1" ] && release_flags+=(--prerelease)
if [ "$LATEST_RELEASE" = "1" ] && [ "$is_draft" = "0" ] && [ "$is_prerelease" = "0" ]; then
    release_flags+=(--latest)
fi

if [ "$release_exists" = "1" ]; then
    say "Updating existing release $TAG in $RELEASE_REPO"
    # The state flags go on this path too. Without them `gh release edit` leaves
    # draft/prerelease exactly as it found them, so nothing could ever promote a
    # draft to a real release, and the appcast decision above would disagree with
    # what GitHub actually serves.
    gh release edit "$TAG" \
        --repo "$RELEASE_REPO" \
        --title "$TITLE" \
        --notes-file "$GITHUB_NOTES_FILE" \
        --draft="$([ "$is_draft" = "1" ] && echo true || echo false)" \
        --prerelease="$([ "$is_prerelease" = "1" ] && echo true || echo false)"
    gh release upload "$TAG" "$ASSET_ZIP" \
        --repo "$RELEASE_REPO" \
        --clobber
else
    say "Creating release $TAG in $RELEASE_REPO"
    # `"${a[@]}"` on an empty array is an unbound-variable error under bash 3.2
    # (what /usr/bin/env bash is on macOS) with `set -u`, so the guarded form has
    # to be at the USE site — reassigning the array beforehand does nothing.
    gh release create "$TAG" "$ASSET_ZIP" \
        --repo "$RELEASE_REPO" \
        ${RELEASE_TARGET_FLAG:+--target "$RELEASE_COMMIT"} \
        --title "$TITLE" \
        --notes-file "$GITHUB_NOTES_FILE" \
        "${release_flags[@]+"${release_flags[@]}"}"

    # `--target` is documented as "Unused if the Git tag already exists", and
    # `gh release delete` leaves the tag behind unless asked to remove it. So the
    # delete-fix-republish loop can silently attach a new artifact to the old
    # tag's commit — the exact "tag says A, binary is B" this flag was added to
    # prevent. Verify rather than trust.
    if [ -n "${RELEASE_TARGET_FLAG:-}" ]; then
        tagged="$(gh api "repos/$RELEASE_REPO/git/ref/tags/$TAG" --jq '.object.sha' 2>/dev/null || true)"
        if [ -n "$tagged" ] && [ "$tagged" != "$RELEASE_COMMIT" ]; then
            die "tag $TAG points at $tagged, but this artifact was built from $RELEASE_COMMIT.
  The tag already existed, so --target was ignored. Delete it with
  'gh release delete $TAG --cleanup-tag --repo $RELEASE_REPO' and re-run."
        fi
    fi
fi

if [ "$publishes_appcast" = "1" ]; then
    push_sparkle_appcast
fi

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

# duoupdater.app is a separate repo that keeps a COMMITTED COPY of CHANGELOG.md,
# refreshed by its own `npm run sync` — nothing about publishing here touches it.
# So the site silently stops at whatever version was last synced, and "remember to
# sync" has now failed twice: 0.3.50–0.3.53 went unpublished for days, the rule was
# written down on 2026-08-22, and 0.3.56 — the very next release — was missed the
# same way. A note nobody reads at the right moment is not a fix; this prints at
# the one moment it is actionable, and says what the site actually has rather than
# reminding in the abstract.
#
# The trap underneath it: the site's own guard drops changelog sections newer than
# the newest LOCAL git tag, and `gh release create` makes the tag on GitHub. Without
# a fetch first, that guard holds back the release that was just published, prints
# one `held back` line, and exits 0 — so `npm run sync` looks like it worked.
site_repo="${DUO_SITE_REPO:-$REPO_ROOT/../duo-updater-site}"
if [ -d "$site_repo/.git" ]; then
    synced="$(git -C "$site_repo" log -1 --pretty=%s 2>/dev/null || true)"
    case "$synced" in
        *"through $version"*)
            printf '\033[1;32m   site     : duoupdater.app already synced through %s\033[0m\n' "$version"
            ;;
        *)
            cat <<EOF

$(printf '\033[1;33m! duoupdater.app is NOT synced yet.\033[0m') Its last sync commit reads:
     ${synced:-<no commits>}

  Run these, in this order — the fetch is load-bearing, not hygiene:

    git -C "$REPO_ROOT" fetch --tags
    cd "$site_repo" && npm run sync

  Then check the sync printed "through $version" and did NOT print "held back",
  and finish with: npm run build && git commit -am "Sync content through $version" && git push
EOF
            ;;
    esac
fi

#!/usr/bin/env bash
# Refuse to ship a build that still carries the developer hooks.
#
#   scripts/check-no-dev-hooks.sh <DuoUpdater.app | binary>
#
# The hooks are compiled only under `DUO_DEV_HOOKS`, which `scripts/install.sh`
# and `scripts/build-cli.sh` set for this Mac's own builds and the release build
# does not. Today that is `GitHubAPIMock`: with DUO_GITHUB_API_MOCK in the
# environment, a build that has it sends GitHub API requests to a local
# stand-in; and `VendorInstaller`'s DUO_SELF_UPDATER_CACHES_DIR, which points
# the local-stash lookup at another caches directory. A release must not even
# read those variables, so each marker below must appear in no Mach-O file of
# what is shipped. Run by `scripts/notarize.sh`
# on the build it notarizes and by `scripts/publish-release.sh` on a CI artifact.
#
# Given an app, it also reads Info.plist's SUAllowsAutomaticUpdates, which
# `scripts/install.sh` sets to NO so a local build never installs a release over
# itself. A release that shipped NO would quietly stop installing its own
# updates for everyone, so anything but YES fails here.
set -euo pipefail

target="${1:?usage: $0 <DuoUpdater.app | binary>}"
[ -e "$target" ] || { echo "✗ $target does not exist" >&2; exit 1; }

# A string only the hooks' code carries — the environment variable each reads.
markers=(DUO_GITHUB_API_MOCK DUO_SELF_UPDATER_CACHES_DIR DUO_RUNNING_APP_TEST_THRESHOLD)

found=0
checked=0
while IFS= read -r -d '' file; do
  # Mach-O files only: the hooks live in code, and a doc or plist naming them
  # is not a hook.
  case "$(file -b "$file")" in *Mach-O*) ;; *) continue ;; esac
  checked=$((checked + 1))
  for marker in "${markers[@]}"; do
    if grep -a -q -- "$marker" "$file"; then
      echo "✗ $file carries the developer hook marker $marker — built with DUO_DEV_HOOKS?" >&2
      found=1
    fi
  done
done < <(find "$target" -type f -print0)

plist="$target/Contents/Info.plist"
if [ -f "$plist" ]; then
  allows="$(/usr/libexec/PlistBuddy -c "Print :SUAllowsAutomaticUpdates" "$plist" 2>/dev/null || echo missing)"
  case "$allows" in
    YES|true) ;;
    *) echo "✗ $plist has SUAllowsAutomaticUpdates = $allows, not YES — built by scripts/install.sh?" >&2
       found=1 ;;
  esac
fi

[ "$checked" -gt 0 ] || { echo "✗ no Mach-O file under $target — checked nothing" >&2; exit 1; }
[ "$found" -eq 0 ] || exit 1
echo "✓ no developer hooks in $checked Mach-O file(s) under $target"

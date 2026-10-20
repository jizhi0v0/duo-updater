#!/bin/bash
# Identity of the .app inside a downloaded .dmg / .zip, read without launching it.
#
#   .claude/skills/coverage-discovery/scripts/check-bundle.sh <file.dmg|file.zip> [...]
#
# The dmg is mounted read-only and detached again; a zip is expanded into a
# temporary directory. Exit codes are read directly, never through a pipe.
set -u
for f in "$@"; do
  t=$(mktemp -d "${TMPDIR:-/tmp}/check-bundle.XXXX")
  case "$f" in
    *.dmg) hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$t/m" "$f" >/dev/null 2>&1 \
             || { echo "== $f: attach failed (already mounted?)"; continue; }; root="$t/m";;
    *.zip) ditto -x -k "$f" "$t/x"; root="$t/x";;
    *) echo "== $f: not a .dmg or .zip"; continue;;
  esac
  app=$(find "$root" -maxdepth 2 -name '*.app' -type d | head -1)
  echo "== $f"
  if [ -z "$app" ]; then echo "  no .app at the top of the archive"; else
    P="$app/Contents/Info.plist"
    for k in CFBundleIdentifier CFBundleName CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion SUFeedURL; do
      printf '  %s=%s\n' "$k" "$(/usr/libexec/PlistBuddy -c "Print :$k" "$P" 2>/dev/null || echo '<none>')"
    done
    exe="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$P")"
    echo "  archs=$(lipo -archs "$exe")"
    codesign -dvv "$app" 2>&1 | grep -E '^(Identifier|TeamIdentifier)=' | sed 's/^/  /'
    codesign --verify --deep --strict "$app" 2>/dev/null; echo "  codesign-verify-exit=$?"
    spctl -a -vv -t exec "$app" 2>&1 | grep -E '^source=' | sed 's/^/  spctl /'
    # Nested apps and login items: a long-running helper keeps executing the old
    # code after the bundle is swapped (SKILL.md, one-click gate).
    find "$app/Contents" -mindepth 2 -maxdepth 4 -name '*.app' -type d | while read -r n; do
      np="$n/Contents/Info.plist"
      printf '  nested %s id=%s LSUIElement=%s LSBackgroundOnly=%s\n' "${n#$app/}" \
        "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$np" 2>/dev/null)" \
        "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$np" 2>/dev/null || echo -)" \
        "$(/usr/libexec/PlistBuddy -c 'Print :LSBackgroundOnly' "$np" 2>/dev/null || echo -)"
    done
    # Everything else that runs without being opened — the places
    # `BundleDiff.privilegedComponents` watches. A system extension or launchd job
    # is not a nested app, and the loop above never saw TaskExplorer's.
    for d in Contents/Library/SystemExtensions Contents/XPCServices Contents/Library/LaunchServices \
             Contents/Library/LaunchAgents Contents/Library/LaunchDaemons; do
      [ -d "$app/$d" ] || continue
      find "$app/$d" -mindepth 1 -maxdepth 1 | while read -r c; do printf '  component %s\n' "${c#$app/}"; done
    done
    # The app naming its own GitHub releases: a sign it updates itself, which a
    # bundle without SUFeedURL or an updater framework does not otherwise show
    # (Lapce reads `api.github.com/repos/lapce/lapce/releases/latest`).
    # `/usr/bin/strings` is a shim that exists without the command-line tools and
    # then asks to install them (a dialog), so ask `xcode-select -p` first.
    if xcode-select -p >/dev/null 2>&1; then
      strings -a "$exe" 2>/dev/null \
        | grep -oE '(api\.github\.com/repos|github\.com)/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases(/latest|/download/)?' \
        | sort -u | head -5 | sed 's/^/  exe-references /'
    else
      echo "  exe-references unavailable: no developer tools (xcode-select -p fails)"
    fi
  fi
  [ -d "$t/m" ] && hdiutil detach "$t/m" >/dev/null 2>&1
  rm -rf "$t"
done

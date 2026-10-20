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
    # PyInstaller writes the executable as `MacOS/aw-qt` (ActivityWatch 0.14.1).
    e=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$P")
    exe="$app/Contents/MacOS/${e#MacOS/}"
    archs=$(lipo -archs "$exe")
    echo "  archs=$archs"
    # The arm64e slice's pointer-authentication ABI (`otool -hv` caps, USR00 or
    # USR01): macOS 15.7.9 kills a USR00 slice even with arm64 beside it.
    # `otool` is a developer-tools shim like `strings` below.
    case " $archs " in *" arm64e "*) xcode-select -p >/dev/null 2>&1 \
      && echo "  arm64e-ptrauth=$(otool -hv -arch arm64e "$exe" | awk 'END {print $4}')";; esac
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
    # An updater with no SUFeedURL: electron-builder's `app-update.yml` (read as
    # `ElectronUpdateConfig.parse` does: flat top-level scalars, one quoting) and a
    # Sparkle.framework whose feed is set at runtime (AltTab), where
    # `AppScanner.sparkleFrameworks` looks: top level and one framework deep.
    yml="$app/Contents/Resources/app-update.yml"
    if [ -f "$yml" ]; then
      printf '  updater electron-updater%s\n' "$(tr -d '\r' < "$yml" \
        | sed -nE "s/^(provider|owner|repo|url):[[:space:]]*['\"]?([^'\"]*)['\"]?[[:space:]]*\$/ \1=\2/p" | tr -d '\n')"
    fi
    for s in "$app/Contents/Frameworks/Sparkle.framework" "$app"/Contents/Frameworks/*.framework/Frameworks/Sparkle.framework; do
      [ -e "$s" ] && printf '  updater sparkle-framework %s\n' "${s#$app/}"
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

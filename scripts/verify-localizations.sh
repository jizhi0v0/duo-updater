#!/usr/bin/env bash
#
# Refuse to deploy a build whose languages did not compile in.
#
# An incremental xcodebuild after an edit to Localizable.xcstrings can empty the
# compiled .lproj folders and not refill them. The app then ships with every
# language directory present and every one of them empty, so every string falls
# back to its English source — while the build reports success, codesign is
# happy, and the version gates are happy. Nothing anywhere says a word. Deleting
# the derived-data directory fixes it in a minute; the cost of not noticing is a
# release that is English for everyone.
#
# The language list comes from the catalog rather than from a list written here,
# so adding a language cannot leave this check testing six of seven.
#
# Usage:  scripts/verify-localizations.sh <path-to-app> [path-to-xcstrings]
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: verify-localizations.sh <path-to-app> [catalog]}"
CATALOG="${2:-$REPO/App/Resources/Localizable.xcstrings}"

die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$APP" ]     || die "no app at $APP"
[ -f "$CATALOG" ] || die "no string catalog at $CATALOG"

langs="$(CATALOG="$CATALOG" python3 -c '
import json, os
catalog = json.load(open(os.environ["CATALOG"], encoding="utf-8"))
langs = {lang for entry in catalog["strings"].values()
              for lang in entry.get("localizations", {})}
langs.add(catalog.get("sourceLanguage", "en"))
print(" ".join(sorted(langs)))
')"
[ -n "$langs" ] || die "could not read the language list out of $CATALOG"

missing=""
for lang in $langs; do
    [ -s "$APP/Contents/Resources/$lang.lproj/Localizable.strings" ] || missing="$missing $lang"
done

if [ -n "$missing" ]; then
    die "the string catalog did not compile into this build — missing or empty:$missing

   Every string would fall back to English, in every language.
   This is what an incremental build does after Localizable.xcstrings changes.
   Delete the derived-data directory and build again:

       rm -rf \"\${DERIVED_DATA:-/tmp/duo-dd}\" && make install"
fi

printf '   %s\n' "$langs"

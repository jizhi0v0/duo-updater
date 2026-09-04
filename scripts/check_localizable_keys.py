#!/usr/bin/env python3
"""Hold Localizable.xcstrings and the source it serves to the same set of keys.

A localizable key is a string the compiler builds from the literal *and* the
format specifier of every interpolated value: an `Int` becomes `%lld`, a
`String` becomes `%@`. Miss that by one character and the lookup finds nothing
and quietly renders the English source — inside a window where everything
around it is translated. That is exactly how the German Backups sheet came to
offer "Delete 49 (21.04 GB)" next to "Alle abwählen": the catalog said
`Delete %@ (%@)` where the runtime asks for `Delete %lld (%@)`.

Nothing else catches it. The build succeeds, `swift test` passes, and the
catalog reports every language "translated" — the key it translated is simply
one nobody asks for. So this compares the two sets directly:

  * a key the source asks for but the catalog lacks  -> renders English
  * a key the catalog carries but no source asks for -> dead weight, and
    indistinguishable from the first case to the next person reading the file

The source side is not guessed. `SWIFT_EMIT_LOC_STRINGS=YES` makes the Swift
compiler write a .stringsdata file per source file containing the exact keys it
emitted, with the file and line each came from — the same data Xcode's own
"Export Localizations" is built on, minus the XLIFF round-trip that rewrites
`%lld` back to `%@`.

The build runs into its own derived-data directory so it never invalidates the
one `make install` uses (the extra build setting would otherwise force a full
rebuild on every switch). The first run is a full build; later runs are
incremental.

Usage:  python3 scripts/check_localizable_keys.py [--derived-data DIR]
Exit:   0 when both sets agree, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CATALOG = REPO / "App" / "Resources" / "Localizable.xcstrings"
PROJECT = REPO / "App" / "DuoUpdater.xcodeproj"
TABLE = "Localizable"

# Keys the catalog is expected to carry without a source site. Keep this list
# empty unless there is a real reason: every entry here is a key that no test
# can prove still works.
ALLOWED_UNREACHABLE: set[str] = set()

# `Text("\(a) · \(b)")` is a localizable key as far as the compiler is
# concerned, but "%@ · %@" holds no words — there is nothing for a translator
# to do with it, and demanding a catalog entry would be busywork that hides the
# keys that matter. Anything with a letter left after the specifiers are
# removed is real copy and must be in the catalog.
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|l?[dfsu@]|%)")


def has_words(key: str) -> bool:
    return any(ch.isalpha() for ch in SPECIFIER.sub("", key))


def build(derived_data: pathlib.Path) -> None:
    """Compile the app with loc-string emission on. Signing is off — this only
    needs the compiler's string metadata, so a fork without the Developer ID
    team can run the check too."""
    if not PROJECT.exists():
        sys.exit(
            f"✗ {PROJECT} is missing — run `xcodegen generate` in App/ first "
            "(scripts/install.sh does it for you)."
        )
    result = subprocess.run(
        [
            "xcodebuild",
            "-project", str(PROJECT),
            "-scheme", "DuoUpdater",
            "-configuration", "Release",
            "-derivedDataPath", str(derived_data),
            "SWIFT_EMIT_LOC_STRINGS=YES",
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO",
            "build",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        tail = "\n".join(result.stdout.splitlines()[-25:])
        sys.exit(f"✗ the extraction build failed:\n{tail}\n{result.stderr[-2000:]}")


def keys_from_source(derived_data: pathlib.Path) -> dict[str, str]:
    """Every key the compiler emitted, mapped to the `file:line` it came from."""
    found: dict[str, str] = {}
    for path in derived_data.rglob("*.stringsdata"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        source = data.get("source", "")
        try:
            source = str(pathlib.Path(source).relative_to(REPO))
        except ValueError:
            pass
        for entry in data.get("tables", {}).get(TABLE, []):
            key = entry.get("key")
            if key is None:
                continue
            line = entry.get("location", {}).get("startingLine")
            found.setdefault(key, f"{source}:{line}" if line else source)
    return found


def report(title: str, detail: str, rows: list[str]) -> None:
    print(f"\n✗ {title}")
    print(f"  {detail}")
    for row in rows:
        print(f"    {row}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--derived-data",
        default=None,
        help="where to build (kept separate from the install build's cache); "
        "defaults to a per-checkout path under /tmp",
    )
    args = parser.parse_args()
    # A per-checkout path, not a fixed one. `make test` runs this in every
    # worktree, and this repo keeps a couple of dozen open, so a shared cache is
    # the likeliest of all of them to be built twice at once — CLAUDE.md records
    # the resulting `database is locked` as something to recognise rather than
    # something to prevent. See scripts/derived_data_path.py.
    derived_data = pathlib.Path(
        args.derived_data
        or subprocess.run(
            [sys.executable, str(REPO / "scripts" / "derived_data_path.py"),
             "loc-check", str(REPO)],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    )

    build(derived_data)
    source = keys_from_source(derived_data)
    if not source:
        sys.exit(
            f"✗ no .stringsdata under {derived_data} — the build emitted no "
            "localizable keys at all, which means this check is testing nothing."
        )

    catalog = set(json.loads(CATALOG.read_text(encoding="utf-8"))["strings"])

    missing = sorted(k for k in set(source) - catalog if has_words(k))
    unreachable = sorted(catalog - set(source) - ALLOWED_UNREACHABLE)

    if missing:
        report(
            f"{len(missing)} key(s) the source asks for are not in the catalog",
            "These render their English source in every language.",
            [f"{source[key]}  {key!r}" for key in missing],
        )
    if unreachable:
        report(
            f"{len(unreachable)} key(s) in the catalog no source site asks for",
            "Translated, never shown. Usually a specifier that does not match "
            "the call site — an Int argument spelled %@ instead of %lld.",
            [repr(key) for key in unreachable],
        )
    if missing or unreachable:
        return 1

    print(f"✓ localizable keys agree — {len(catalog)} in the catalog, all reachable")
    return 0


if __name__ == "__main__":
    sys.exit(main())

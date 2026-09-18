#!/usr/bin/env python3
"""Hold every translation to the arguments its key actually passes.

A localizable key carries the call's argument list in its format specifiers:
`String(localized: "There are \\(count) backups, \\(size)")` becomes the key
`There are %lld backups, %@`, and at runtime CoreFoundation walks that format
filling it from (Int, String) in order. A translation may reorder the words and
a plural variant may reword the whole sentence, but neither may change *which
argument a specifier reads*.

Change it and nothing complains until the moment that variant is chosen. This
check exists because of one that reached a user's machine:

    "one":   "There is 1 backup on this Mac, %@."
    "other": "There are %lld backups on this Mac, %@."

The singular spells the number out, so it carries no `%lld` — and `%@`, being
the first specifier, therefore read argument one, the `Int`. The app died in
`objc_opt_respondsToSelector` at address 0x1, the count itself dereferenced as
an object. Every other plural category was fine, so it waited for a Mac with
exactly one backup to exist. The fix is an explicit position: `%2$@`.

Neither existing gate can see this. `check_localizable_keys.py` compares the
set of keys the source asks for against the set the catalog carries and never
reads a value; `verify-localizations.sh` asks whether a language compiled into
the bundle at all.

What is checked, per localization and per plural category:

  * every specifier's argument slot must hold the type the key declares there —
    the rule that catches the crash above, since an implicit `%@` in a variant
    missing its `%lld` lands on slot 1;
  * a named substitution (`%#@name@`) is read through its own `argNum` and
    `formatSpecifier`, which is how Xcode writes plurals and is *not* an error;
  * a slot past the end of the key's argument list;
  * positional and implicit specifiers mixed in one string, which CoreFoundation
    does not define an order for.

Usage:  python3 scripts/check_localizable_specifiers.py [--catalog PATH]
Exit:   0 when every variant reads the arguments its key passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CATALOG = REPO / "App" / "Resources" / "Localizable.xcstrings"

# A named substitution, e.g. `%#@releases@`. Matched first and removed, because
# it ends in `@` and would otherwise read as an object specifier.
SUBSTITUTION = re.compile(r"%#@([^@]+)@")

# One printf specifier. `%%` is a literal percent and carries no argument.
SPECIFIER = re.compile(
    r"%(?:(\d+)\$)?"           # 1: explicit argument position
    r"[-+ #0']*"               # flags
    r"(?:\d+|\*)?"             # width
    r"(?:\.(?:\d+|\*))?"       # precision
    r"(hh|h|ll|l|q|L|z|t|j)?"  # 2: length
    r"([@dDiuUxXoOfFeEgGaAcCsSpn%])"  # 3: conversion
)

# What a slot must be handed. Only the class matters: a mismatch inside one
# class is a formatting bug, a mismatch across one is a crash.
CLASS_OF = {
    "@": "object",
    "d": "integer", "D": "integer", "i": "integer",
    "u": "integer", "U": "integer",
    "x": "integer", "X": "integer", "o": "integer", "O": "integer",
    "f": "float", "F": "float", "e": "float", "E": "float",
    "g": "float", "G": "float", "a": "float", "A": "float",
    "c": "character", "C": "character",
    "s": "cstring", "S": "cstring",
    "p": "pointer",
}


class Mismatch(Exception):
    """A variant that would read an argument the call did not pass there."""


def slots(text: str) -> list[tuple[int, str]]:
    """The (slot, class) pairs `text` consumes, substitutions removed already.

    Raises `Mismatch` when positional and implicit specifiers are mixed: CF
    leaves the order undefined, so the honest answer is to refuse rather than
    pick one and be right half the time.
    """
    out: list[tuple[int, str]] = []
    implicit = 0
    saw_positional = saw_implicit = False
    for match in SPECIFIER.finditer(text):
        position, _, conversion = match.groups()
        if conversion == "%":
            continue
        if position:
            saw_positional = True
            slot = int(position)
        else:
            saw_implicit = True
            implicit += 1
            slot = implicit
        out.append((slot, CLASS_OF[conversion]))
    if saw_positional and saw_implicit:
        raise Mismatch("mixes %1$-style positions with implicit ones")
    return out


def declared(key: str) -> dict[int, str]:
    """What the key says each argument slot is."""
    return dict(slots(SUBSTITUTION.sub("", key)))


def substitution_slots(
    text: str, substitutions: dict
) -> list[tuple[int, str, str]]:
    """The (slot, class, name) each `%#@name@` in `text` consumes."""
    out = []
    for name in SUBSTITUTION.findall(text):
        spec = substitutions.get(name)
        if spec is None:
            raise Mismatch(f"uses %#@{name}@ with no substitution of that name")
        conversion = str(spec.get("formatSpecifier", ""))[-1:]
        if conversion not in CLASS_OF:
            raise Mismatch(f"substitution {name} has no usable formatSpecifier")
        out.append((int(spec.get("argNum", 0)), CLASS_OF[conversion], name))
    return out


def variants(localization: dict) -> list[tuple[str, str]]:
    """Every (label, value) a localization can render, plurals included."""
    out: list[tuple[str, str]] = []
    unit = localization.get("stringUnit")
    if unit and "value" in unit:
        out.append(("", unit["value"]))
    for kind, table in localization.get("variations", {}).items():
        for category, entry in table.items():
            inner = entry.get("stringUnit")
            if inner and "value" in inner:
                out.append((f"{kind}.{category}", inner["value"]))
    return out


def check_value(value: str, want: dict[int, str], substitutions: dict) -> None:
    """Raise `Mismatch` when `value` reads an argument that is not there."""
    for slot, kind, name in substitution_slots(value, substitutions):
        if slot not in want:
            raise Mismatch(f"substitution {name} takes argument {slot}, which the key does not pass")
        if want[slot] != kind:
            raise Mismatch(
                f"substitution {name} reads argument {slot} as {kind}, "
                f"but the key passes {want[slot]} there")
    for slot, kind in slots(SUBSTITUTION.sub("", value)):
        if slot not in want:
            raise Mismatch(f"reads argument {slot}, which the key does not pass")
        if want[slot] != kind:
            raise Mismatch(
                f"reads argument {slot} as {kind}, but the key passes "
                f"{want[slot]} there — say %{slot}${'@' if want[slot] == 'object' else 'lld'} "
                f"to name the one you mean")


def check_substitution_bodies(substitutions: dict) -> list[str]:
    """A substitution's own plural bodies must use the specifier it declares."""
    problems = []
    for name, spec in substitutions.items():
        conversion = str(spec.get("formatSpecifier", ""))[-1:]
        if conversion not in CLASS_OF:
            continue
        want = CLASS_OF[conversion]
        for kind, table in spec.get("variations", {}).items():
            for category, entry in table.items():
                value = entry.get("stringUnit", {}).get("value", "")
                for _, got in slots(SUBSTITUTION.sub("", value)):
                    if got != want:
                        problems.append(
                            f"{name}.{kind}.{category} formats a {got} where the "
                            f"substitution declares {want}")
    return problems


def check(catalog: pathlib.Path) -> tuple[list[str], int, int]:
    """Returns (failures, keys examined, variants examined)."""
    data = json.loads(catalog.read_text())
    failures: list[str] = []
    keys = variants_seen = 0

    for key, entry in sorted(data.get("strings", {}).items()):
        try:
            want = declared(key)
        except Mismatch as bad:
            failures.append(f"key itself {bad}: {key!r}")
            continue
        if not want:
            continue
        keys += 1
        for language, localization in sorted(entry.get("localizations", {}).items()):
            substitutions = localization.get("substitutions", {})
            for problem in check_substitution_bodies(substitutions):
                failures.append(f"{language}  {problem}\n      key: {key!r}")
            for label, value in variants(localization):
                variants_seen += 1
                try:
                    check_value(value, want, substitutions)
                except Mismatch as bad:
                    where = f"{language} {label}".strip()
                    failures.append(
                        f"{where}  {bad}\n      key:   {key!r}\n      value: {value!r}")
    return failures, keys, variants_seen


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default=str(CATALOG))
    args = parser.parse_args()

    catalog = pathlib.Path(args.catalog)
    failures, keys, variants_seen = check(catalog)

    # A run that examined almost nothing passes for the wrong reason. The
    # catalog this guards has 159 keys carrying specifiers; a floor well under
    # that still fails loudly if the parse silently stops matching.
    if keys < 50:
        print(f"\n✗ only {keys} key(s) with specifiers examined in {catalog} — "
              "too few to be a real run.")
        return 1

    if failures:
        print(f"\n✗ {len(failures)} translation(s) read an argument the call does not pass")
        print("  Each would format an argument as the wrong type at runtime; an "
              "integer read as an object is a crash, not a typo.")
        for row in failures:
            print(f"    {row}")
        return 1

    print(f"✓ format specifiers agree with their keys — {keys} key(s), "
          f"{variants_seen} variant(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

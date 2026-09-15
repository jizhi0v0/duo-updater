#!/usr/bin/env python3
"""Hold every recipe family file to the JSON5 subset it is written in, and refuse
a key written twice.

Run by `make test`.

    python3 scripts/check_recipe_json5.py

## Why the decoder is not enough

The family files under `DuoUpdaterCore/Sources/DuoUpdaterCore/Resources/Recipes/`
are read by `JSONDecoder` with `allowsJSON5` (`RecipeFamilyFile`). The dialect
decided for them is narrower: plain JSON plus whole-line `//` comments. The
decoder accepts the rest of JSON5 too — trailing commas, `/* */`, end-of-line
`//`, single quotes, unquoted keys — so nothing at runtime would ever say a file
had left the dialect, and every such file is one more shape the next tool that
reads these files (this script, `check_recipe_snapshots.py`, the channel-discovery
command, a future generator) has to understand. Each of them reads comments as
whole lines; an end-of-line comment is invisible to all of them.

The second reason is worse. Every Foundation JSON reader — `JSONDecoder` with or
without `allowsJSON5`, and `JSONSerialization` — keeps the FIRST value of a key
written twice in one object and says nothing (measured in step 3's S0). A second
`"versionPattern"` added below the first reads, in review, like the change, and
does nothing at all. Python's `json` with an `object_pairs_hook` sees both.

## What it checks, per file

  * Outside a string, on a line that is not a whole-line comment: no `/*` or
    `//` (a block or end-of-line comment), no `'` (a single-quoted string), no
    bare word other than `true`, `false` and `null` (an unquoted key, or `NaN`
    and `Infinity`), no comma before a closing `]` or `}` (whole-line comments in
    between are skipped), and no string left open at the end of its line (JSON5's
    backslash line continuation).
  * With whole-line comments blanked, `json.loads` must accept the text — strict
    JSON, so anything the list above does not name still fails here — and no
    object at any depth may hold a key twice.

It does not decode recipes (`AppRecipeIndexTests` and the goldens do that), and
it says nothing about comments beyond their being whole lines.

A floor: finding no family file is a failure, not a pass — a moved directory
would otherwise make this check agree with everything.
"""

import json
import pathlib
import sys

RECIPE_DATA = "DuoUpdaterCore/Sources/DuoUpdaterCore/Resources/Recipes"
EXTENSION = ".json5"
WORDS = {"true", "false", "null"}


class DuplicateKey(Exception):
    pass


def is_comment(line):
    return line.lstrip().startswith("//")


def dialect_problems(text):
    """[(line, column, kind, message)] for everything outside the dialect."""
    found = []
    lines = text.split("\n")
    # (line index, column) of the last comma outside a string, cleared by any
    # other token; a closing bracket while it is set is a trailing comma.
    comma = None
    for number, line in enumerate(lines, 1):
        if is_comment(line):
            continue
        i, in_string = 0, False
        while i < len(line):
            ch = line[i]
            if in_string:
                if ch == "\\":
                    i += 2
                    continue
                if ch == '"':
                    in_string = False
                i += 1
                continue
            col = i + 1
            if ch == '"':
                in_string = True
                comma = None
            elif ch == "/" and line[i + 1:i + 2] == "*":
                found.append((number, col, "block-comment",
                              "`/* */` comment — only whole-line `//` comments are allowed"))
                break
            elif ch == "/" and line[i + 1:i + 2] == "/":
                found.append((number, col, "end-of-line-comment",
                              "`//` after code on the same line — move the comment to its own line"))
                break
            elif ch == "'":
                found.append((number, col, "single-quote", "single-quoted string — use double quotes"))
                break
            elif ch.isdigit() or ch == "-":
                # A number, exponent included, so `1e5` is not read as a word.
                # Its exact form is json.loads's business.
                j = i
                while j < len(line) and (line[j].isalnum() or line[j] in ".+-"):
                    j += 1
                comma = None
                i = j
                continue
            elif ch.isalpha() or ch in "_$":
                j = i
                while j < len(line) and (line[j].isalnum() or line[j] in "_$"):
                    j += 1
                word = line[i:j]
                if word not in WORDS:
                    rest = line[j:].lstrip()
                    if rest.startswith(":"):
                        found.append((number, col, "unquoted-key",
                                      f"unquoted key `{word}` — write \"{word}\""))
                    else:
                        found.append((number, col, "bare-word",
                                      f"`{word}` is not JSON (only true, false, null)"))
                    break
                comma = None
                i = j
                continue
            elif ch == ",":
                comma = (number, col)
            elif ch in "]}":
                if comma:
                    found.append((comma[0], comma[1], "trailing-comma",
                                  f"trailing comma before `{ch}` on line {number}"))
                comma = None
            elif not ch.isspace():
                comma = None
            i += 1
        if in_string:
            found.append((number, len(line), "open-string",
                          "string runs past the end of the line — JSON strings are one line"))
    return found


def pairs(items):
    keys = [k for k, _ in items]
    seen = set()
    for key in keys:
        if key in seen:
            raise DuplicateKey(f"key `{key}` appears twice in one object (its keys: {', '.join(keys)}) — "
                               "a JSON decoder silently keeps the first")
        seen.add(key)
    return dict(items)


def reject_constant(name):
    raise ValueError(f"`{name}` is not JSON")


def problems(text):
    """[(line, column, kind, message)] for one file's text."""
    found = dialect_problems(text)
    if found:
        # json.loads would only restate the first of these, less clearly.
        return found
    blanked = "\n".join("" if is_comment(line) else line for line in text.split("\n"))
    try:
        json.loads(blanked, object_pairs_hook=pairs, parse_constant=reject_constant)
    except DuplicateKey as error:
        return [(0, 0, "duplicate-key", str(error))]
    except json.JSONDecodeError as error:
        return [(error.lineno, error.colno, "not-json", error.msg)]
    except ValueError as error:
        return [(0, 0, "not-json", str(error))]
    return []


def review(root):
    base = root / RECIPE_DATA
    found = {"missing": not base.is_dir(), "files": 0, "problems": []}
    if found["missing"]:
        return found
    for path in sorted(base.glob("*" + EXTENSION)):
        found["files"] += 1
        rel = path.relative_to(root)
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError as error:
            found["problems"].append((rel, 0, 0, "not-utf8", str(error)))
            continue
        found["problems"].extend((rel, *p) for p in problems(text))
    return found


def main(root=None, minimum=1):
    root = root or pathlib.Path(__file__).resolve().parent.parent
    found = review(root)
    if found["missing"]:
        print(f"✗ {RECIPE_DATA} is not under {root} — fix the path rather than "
              "checking nothing.", file=sys.stderr)
        return 1
    if found["files"] < minimum:
        print(f"✗ only {found['files']} recipe {EXTENSION} files under {RECIPE_DATA} — "
              f"expected at least {minimum}, so this checked nothing real.", file=sys.stderr)
        return 1
    if not found["problems"]:
        print(f"✓ recipe {EXTENSION} files in dialect, no duplicate keys — {found['files']} files")
        return 0
    for rel, line, col, kind, message in found["problems"]:
        where = f"{rel}:{line}:{col}" if line else f"{rel}"
        print(f"✗ {where}: [{kind}] {message}", file=sys.stderr)
    print(f"\n{len(found['problems'])} problem(s). Recipe files are plain JSON plus whole-line "
          "`//` comments (RecipeFamilyFile).", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

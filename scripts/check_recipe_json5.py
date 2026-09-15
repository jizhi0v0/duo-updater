#!/usr/bin/env python3
r"""Hold every recipe family file to the JSON5 subset it is written in, and refuse
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

## What it checks

  * **The directory holds only families.** Every entry of the directory must be a
    regular file named `<slug>.json5` (not a symlink, a subdirectory, a dotfile,
    `Foo.JSON5` or `foo.json`): `.copy` ships all of them and the loader traps on
    any other (`recipe_families.py`).
  * **The family count reconciles** with the goldens: `.swift` family files plus
    `.json5` family files must equal the number of goldens, which Swift writes
    one per family it loads.

Per file:

  * **No character that ends a line for one reader and not another.** Swift's
    JSON5 scanner ends a `//` comment at `\r` as well as `\n` (measured: a
    comment line ending in `\r` followed by a key on the same `\n`-line decodes
    that key, which a reader splitting on `\n` blanks as comment — hiding the first
    of two duplicate keys). So `\r`, every other C0/C1 control except tab and
    newline, DEL, U+2028, U+2029 and U+FEFF are refused anywhere in the file, and
    a line's indentation may only be spaces and tabs (Python's `lstrip()` also
    strips NBSP and `\x1c`–`\x1f`, which Swift does not skip). A comment line is
    exactly `^[ \t]*//`.
  * Outside a string, on a line that is not a whole-line comment: no `/*` or
    `//` (a block or end-of-line comment), no `'` (a single-quoted string), no
    bare word other than `true`, `false` and `null` (an unquoted key, or `NaN`
    and `Infinity`), no comma before a closing `]` or `}` (whole-line comments in
    between are skipped), and no string left open at the end of its line (JSON5's
    backslash line continuation).
  * With whole-line comments blanked, `json.loads` must accept the text — strict
    JSON, so anything the list above does not name still fails here — and no
    object at any depth may hold a key twice.
  * No decoded string holds NUL or a lone surrogate (`\u0000`, `\uD800`): Python
    accepts both escapes, Foundation refuses both (measured), so the file would
    pass here and trap at runtime.

It does not decode recipes (`AppRecipeIndexTests` and the goldens do that), and
it says nothing about comments beyond their being whole lines.

A floor: finding no family file is a failure, not a pass — a moved directory
would otherwise make this check agree with everything.
"""

import json
import pathlib
import re
import sys
import unicodedata

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import recipe_families as families  # noqa: E402

RECIPE_DATA = families.RECIPE_DATA
EXTENSION = ".json5"
WORDS = {"true", "false", "null"}
# Characters that some reader of these files treats as a line break or skips as
# whitespace while another does not. Tab and newline are the only controls allowed.
FORBIDDEN = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f\u2028\u2029\ufeff]")
COMMENT = re.compile(r"[ \t]*//")


class DuplicateKey(Exception):
    pass


def is_comment(line):
    return COMMENT.match(line) is not None


def character_problems(text):
    """Forbidden characters anywhere, and indentation that is not spaces and tabs."""
    found = []
    for number, line in enumerate(text.split("\n"), 1):
        for m in FORBIDDEN.finditer(line):
            found.append((number, m.start() + 1, "control-character",
                          f"U+{ord(m.group()):04X} — only tab and newline are allowed "
                          "(a `\\r` ends a `//` comment for Swift but not for a line reader)"))
        indent = len(line) - len(line.lstrip(" \t"))
        if indent < len(line) and line[indent].isspace() and not FORBIDDEN.match(line[indent]):
            found.append((number, indent + 1, "indentation",
                          f"U+{ord(line[indent]):04X} in the indentation — only spaces and tabs"))
    return found


def string_problems(value, path="<top level>"):
    """NUL or a lone surrogate in any decoded key or string."""
    found = []
    def bad(text):
        return "\x00" in text or any(0xD800 <= ord(ch) <= 0xDFFF for ch in text)
    if isinstance(value, dict):
        for key, item in value.items():
            if bad(key):
                found.append((0, 0, "bad-escape", f"key under {path} holds NUL or a lone surrogate"))
            found.extend(string_problems(item, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(string_problems(item, f"{path}[{index}]"))
    elif isinstance(value, str) and bad(value):
        found.append((0, 0, "bad-escape",
                      f"{path} holds NUL or a lone surrogate (`\\u0000`, `\\uD800`) — Foundation refuses it"))
    return found


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
    # Compared after NFC, because Swift `String` equality and hashing are on
    # canonical equivalents: `"com.example.Keka"` and the same with U+212A KELVIN
    # SIGN, or precomposed vs decomposed `café`, are distinct byte strings that a
    # `[String: …]` table silently collapses to one. Python's own dict does not,
    # so json.loads keeps both and this is the only place it is caught.
    seen = {}
    for key in keys:
        folded = unicodedata.normalize("NFC", key)
        if folded in seen:
            first = seen[folded]
            spellings = f"`{first}` and `{key}`" if first != key else f"`{key}`"
            note = "" if first == key else " (canonically equal after NFC)"
            raise DuplicateKey(
                f"key {spellings} appear twice in one object{note} (its keys: {', '.join(keys)}); "
                "a JSON decoder silently keeps the first", folded)
        seen[folded] = key
    return dict(items)


def reject_constant(name):
    raise ValueError(f"`{name}` is not JSON")


def problems(text):
    """[(line, column, kind, message)] for one file's text."""
    found = character_problems(text) or dialect_problems(text)
    if found:
        # json.loads would only restate the first of these, less clearly.
        return found
    blanked = "\n".join("" if is_comment(line) else line for line in text.split("\n"))
    try:
        value = json.loads(blanked, object_pairs_hook=pairs, parse_constant=reject_constant)
    except DuplicateKey as error:
        # The hook cannot see positions; name every line whose key folds to the same
        # NFC form (so a decomposed spelling in the file is still found).
        folded = error.args[1]
        where = [str(n) for n, line in enumerate(text.split("\n"), 1)
                 if not is_comment(line) and '"' in line
                 and unicodedata.normalize("NFC", line.split(":", 1)[0]).find(f'"{folded}"') >= 0]
        return [(0, 0, "duplicate-key", f"{error.args[0]} — on line(s) {', '.join(where)}")]
    except json.JSONDecodeError as error:
        return [(error.lineno, error.colno, "not-json", error.msg)]
    except ValueError as error:
        return [(0, 0, "not-json", str(error))]
    return string_problems(value)


def review(root):
    base = root / RECIPE_DATA
    found = {"missing": not base.is_dir(), "files": 0, "problems": [], "reconcile": None}
    if found["missing"]:
        return found
    for path, layout in families.data_entries(root):
        rel = path.relative_to(root)
        if layout:
            found["problems"].append((rel, 0, 0, "not-a-family-file",
                                      f"{layout} — {RECIPE_DATA} may hold only regular "
                                      "<slug>.json5 files; the loader traps on anything else"))
            continue
        found["files"] += 1
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError as error:
            found["problems"].append((rel, 0, 0, "not-utf8", str(error)))
            continue
        found["problems"].extend((rel, *p) for p in problems(text))
    swift = len(families.swift_family_files(root))
    found["reconcile"] = families.reconcile(
        root, swift + found["files"],
        f"{swift} .swift + {found['files']} .json5 family files")
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
    if found["reconcile"]:
        print(f"✗ {found['reconcile']}", file=sys.stderr)
    if not found["problems"] and not found["reconcile"]:
        print(f"✓ recipe {EXTENSION} files in dialect, no duplicate keys — {found['files']} files; "
              f"family files reconcile with {families.golden_count(root)} goldens")
        return 0
    for rel, line, col, kind, message in found["problems"]:
        where = f"{rel}:{line}:{col}" if line else f"{rel}"
        print(f"✗ {where}: [{kind}] {message}", file=sys.stderr)
    print(f"\n{len(found['problems'])} problem(s). Recipe files are plain JSON plus whole-line "
          "`//` comments (RecipeFamilyFile).", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

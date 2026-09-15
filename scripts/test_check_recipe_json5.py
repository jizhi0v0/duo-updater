#!/usr/bin/env python3
"""Regression tests for `check_recipe_json5`. Run by `make test`.

    python3 scripts/test_check_recipe_json5.py

Every case names the mutation it catches. The valid fixture is shaped like the
real family files: comment blocks before entries, regexes with escaped
backslashes, URLs whose `//` sits inside a string, prose with apostrophes.
"""

import contextlib
import io
import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_recipe_json5 as crj  # noqa: E402

VALID = """\
{
  "probes": [
    // History: docs/app-audits/zz-fixture.md#历史与实测
    // It's the stable feed; `/* not a comment */` and a trailing `,]` in prose.
    {
      "bundleID": "zz.fixture",
      "url": "https://example.invalid/mac/stable/index.xml",
      "mode": {"kind": "responseBody"},
      "versionPattern": "<title>Fixture\\\\s+([0-9]+\\\\.[0-9]+)</title> it's \\"//\\" '/*'",
      "selectHighest": true,
      "maxEntries": 1e2,
      "install": {
        // A comment before a field.
        "urlSource": {"kind": "fixed", "url": "https://example.invalid/a.zip"},
        "kind": "zip"
      }
    }
  ],
  "sparkleFeeds": {"zz.fixture": "https://example.invalid/appcast.xml"},
  "changelogPages": {}
}
"""


def kinds(text):
    return [kind for _, _, kind, _ in crj.problems(text)]


class Dialect(unittest.TestCase):

    # Mutation: treat a `/` or `'` inside a string as outside it, or forget escapes.
    def test_the_real_shapes_pass(self):
        self.assertEqual(crj.problems(VALID), [])

    # Mutation: delete the `/*` branch (json.loads alone would still fail the file,
    # as `not-json`, which this names more precisely).
    def test_a_block_comment_is_refused(self):
        self.assertEqual(kinds(VALID.replace('"selectHighest": true,',
                                             '/* why */ "selectHighest": true,')),
                         ["block-comment"])
        self.assertEqual(kinds(VALID.replace("    // A comment before a field.",
                                             "    /* A comment before a field. */")),
                         ["block-comment"])

    # Mutation: delete the end-of-line `//` branch, or accept a `//` anywhere on a
    # line that has code before it.
    def test_an_end_of_line_comment_is_refused(self):
        self.assertEqual(kinds(VALID.replace('"selectHighest": true,',
                                             '"selectHighest": true, // highest')),
                         ["end-of-line-comment"])

    # Mutation: stop clearing `comma` on other tokens (the valid fixture then fails),
    # or stop checking it at `]`/`}`.
    def test_a_trailing_comma_is_refused_in_objects_and_arrays(self):
        self.assertEqual(kinds(VALID.replace('"kind": "zip"', '"kind": "zip",')),
                         ["trailing-comma"])
        self.assertEqual(kinds(VALID.replace("    }\n  ],", "    },\n  ],")),
                         ["trailing-comma"])

    # Mutation: let a whole-line comment reset the pending comma.
    def test_a_trailing_comma_before_a_comment_line_is_still_trailing(self):
        text = VALID.replace('"kind": "zip"\n', '"kind": "zip",\n        // last\n')
        self.assertEqual(kinds(text), ["trailing-comma"])

    # Mutation: delete the single-quote branch.
    def test_a_single_quoted_string_is_refused(self):
        self.assertEqual(kinds(VALID.replace('"kind": "zip"', "\"kind\": 'zip'")),
                         ["single-quote"])

    # Mutation: accept any bare word, or report an unquoted key as a bare word.
    def test_an_unquoted_key_and_a_bare_word_are_refused(self):
        self.assertEqual(kinds(VALID.replace('"selectHighest": true', "selectHighest: true")),
                         ["unquoted-key"])
        self.assertEqual(kinds(VALID.replace('"selectHighest": true', '"selectHighest": NaN')),
                         ["bare-word"])

    # Mutation: stop reporting a string still open at the end of its line.
    def test_a_line_continuation_is_refused(self):
        text = VALID.replace('"https://example.invalid/a.zip"', '"https://example.invalid/\\\n/a.zip"')
        self.assertIn("open-string", kinds(text))

    # Mutation: drop the `object_pairs_hook`, or check only the top-level object.
    def test_a_duplicate_key_is_refused_at_any_depth(self):
        top = VALID.replace('  "changelogPages": {}', '  "changelogPages": {},\n  "sparkleFeeds": {}')
        nested = VALID.replace('"kind": "zip"', '"kind": "zip",\n        "kind": "dmg"')
        deepest = VALID.replace('{"kind": "fixed", ', '{"kind": "fixed", "kind": "fixed", ')
        for name, text in {"top": top, "nested": nested, "deepest": deepest}.items():
            with self.subTest(name):
                self.assertEqual(crj.dialect_problems(text), [])
                self.assertEqual(kinds(text), ["duplicate-key"])

    # Mutation: compare keys byte-for-byte instead of on NFC. Swift `String` hashes
    # on canonical equivalents, so a `[String: …]` table keeps one of these; the
    # decoder and a byte-wise check both keep both and say nothing.
    def test_canonically_equal_keys_are_refused(self):
        cases = {
            # U+212A KELVIN SIGN in "Keka" vs ASCII "K": NFC folds the sign to "K".
            "kelvin": ("com.example.\u212Aeka", "com.example.Keka"),
            # Decomposed cafe\u0301 (e + combining acute) vs precomposed caf\u00e9.
            "cafe": ("cafe\u0301", "caf\u00e9"),
        }
        for name, (first, second) in cases.items():
            with self.subTest(name):
                assert first != second, "the two spellings must be distinct byte strings"
                text = VALID.replace(
                    '  "changelogPages": {}',
                    f'  "changelogPages": {{"{first}": "x", "{second}": "y"}}')
                self.assertEqual(crj.dialect_problems(text), [])
                problems = crj.problems(text)
                self.assertEqual([k for _, _, k, _ in problems], ["duplicate-key"])
                # Both spellings, and "NFC", are named.
                message = problems[0][3]
                self.assertIn(first, message)
                self.assertIn(second, message)
                self.assertIn("NFC", message)

    # Mutation: stop blanking whole-line comments before json.loads (every file
    # with a comment fails), or blank a line that has code before `//`.
    def test_anything_else_outside_json_fails_json_loads(self):
        self.assertEqual(kinds(VALID.replace('"maxEntries": 1e2', '"maxEntries": 0x1F')), ["not-json"])
        self.assertEqual(kinds(VALID.replace('"maxEntries": 1e2', '"maxEntries": +1')), ["not-json"])


class Characters(unittest.TestCase):
    """Characters one reader treats as a line break, or skips as whitespace, while
    another does not. The first case is the reviewer's reproduction: Foundation ends
    the `//` comment at `\r` and decodes the evil URL as the first of two keys."""

    HIDDEN = ('{\n "sparkleFeeds": {\n // note\r"com.x": "https://evil.example/a.xml",\n'
              ' "com.x": "https://good.example/a.xml"\n }\n}\n')

    # Mutation: drop `\r` (`\x0d`) from FORBIDDEN. The file then passes: the comment
    # line is blanked whole, and with it the hidden duplicate.
    def test_a_carriage_return_hiding_a_duplicate_is_refused(self):
        self.assertEqual(kinds(self.HIDDEN), ["control-character"])
        self.assertEqual(kinds(self.HIDDEN.replace("\r", "\n")), ["duplicate-key"])

    # Mutation: narrow FORBIDDEN to `\r`, or drop its C1 / U+2028 / U+2029 / U+FEFF parts.
    def test_every_other_line_breaking_or_invisible_character_is_refused(self):
        for name, ch in {"VT": "\x0b", "FF": "\x0c", "FS": "\x1c", "US": "\x1f", "DEL": "\x7f",
                         "NEL": "\x85", "LS": "\u2028", "PS": "\u2029", "BOM": "\ufeff",
                         "NUL": "\x00"}.items():
            with self.subTest(name):
                text = VALID.replace("    // A comment before a field.", f"    // A comment{ch} before a field.")
                self.assertEqual(kinds(text), ["control-character"])

    # Mutation: let `character_problems` skip indentation, or use `lstrip()`
    # (which strips NBSP) to find it.
    def test_non_ascii_whitespace_in_indentation_is_refused(self):
        for name, ch in {"NBSP": "\u00a0", "EM SPACE": "\u2003", "IDEOGRAPHIC SPACE": "\u3000"}.items():
            with self.subTest(name):
                text = VALID.replace("    // A comment before a field.", f"  {ch}  // A comment before a field.")
                self.assertEqual(kinds(text), ["indentation"])
        # Inside comment prose, the same characters are only text.
        self.assertEqual(kinds(VALID.replace("A comment before", "A comment\u3000before")), [])

    # Mutation: go back to `line.lstrip().startswith("//")` for `is_comment`.
    def test_a_comment_line_is_spaces_and_tabs_then_slashes(self):
        self.assertTrue(crj.is_comment(" \t // x"))
        self.assertFalse(crj.is_comment("\u00a0// x"))

    # Mutation: drop `string_problems` from `problems`.
    def test_a_nul_or_lone_surrogate_escape_is_refused(self):
        for name, escape in {"NUL": "\\u0000", "high": "\\uD800", "low": "\\uDC00"}.items():
            with self.subTest(name):
                text = VALID.replace('"kind": "zip"', f'"kind": "zip{escape}"')
                self.assertEqual(kinds(text), ["bad-escape"])
        self.assertEqual(kinds(VALID.replace('"kind": "zip"', '"kind": "zip\\uD83D\\uDE00"')), [])


class Tree(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="duo-json5-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.data = self.root / crj.RECIPE_DATA
        self.data.mkdir(parents=True)
        (self.root / crj.families.RECIPES).mkdir(parents=True)
        self.goldens = self.root / crj.families.GOLDENS
        self.goldens.mkdir(parents=True)

    def write(self, name, text, golden=True):
        (self.data / name).write_text(text)
        if golden and name.endswith(".json5"):
            (self.goldens / (name[:-len(".json5")] + ".txt")).write_text("golden\n")

    def main(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()) as out, \
                contextlib.redirect_stderr(io.StringIO()) as err:
            code = crj.main(root=self.root, **kwargs)
        return code, out.getvalue() + err.getvalue()

    # Mutation: `return found` without reporting a missing directory.
    def test_a_missing_directory_fails(self):
        shutil.rmtree(self.root / "DuoUpdaterCore")
        self.assertEqual(self.main(minimum=0)[0], 1)

    # Mutation: delete the floor, or lower `main`'s default below 1.
    def test_no_files_fails_by_default(self):
        self.write("zz-fixture.json", VALID)  # wrong extension: refused, never counted
        code, output = self.main()
        self.assertEqual(code, 1)
        self.assertIn("only 0 recipe .json5 files", output)

    # Mutation: glob `*.json5` in `review` again (non-families silently skipped), or
    # drop a branch of `recipe_families.data_entries`.
    def test_anything_but_a_regular_slug_json5_file_is_refused(self):
        self.write("zz-fixture.json5", VALID)
        cases = {
            "other extension": lambda: (self.data / "zz-other.json").write_text(VALID),
            "upper-case extension": lambda: (self.data / "zz-other.JSON5").write_text(VALID),
            "dotfile": lambda: (self.data / ".DS_Store").write_bytes(b"\x00"),
            "subdirectory": lambda: (self.data / "sub").mkdir(),
            "file in a subdirectory": lambda: ((self.data / "sub").mkdir(), (self.data / "sub" / "zz-deep.json5").write_text(VALID)),
            "symlink": lambda: (self.data / "zz-link.json5").symlink_to(self.data / "zz-fixture.json5"),
            "leading dash": lambda: (self.data / "-zz.json5").write_text(VALID),
        }
        for name, make in cases.items():
            with self.subTest(name):
                make()
                code, output = self.main()
                self.assertEqual(code, 1, output)
                self.assertIn("[not-a-family-file]", output)
                if name == "symlink":
                    # The regular-file branch refuses it too (it does not follow
                    # links); this pins that the reason given is the real one.
                    self.assertIn("is a symbolic link", output)
                for entry in list(self.data.iterdir()):
                    if entry.name != "zz-fixture.json5":
                        shutil.rmtree(entry) if entry.is_dir() and not entry.is_symlink() else entry.unlink()

    # Mutation: delete the reconcile check in `main`, or count only `.json5` files.
    def test_the_family_count_must_reconcile_with_the_goldens(self):
        self.write("zz-fixture.json5", VALID)
        (self.root / crj.families.RECIPES / "aa-swift.swift").write_text("")
        code, output = self.main()
        self.assertEqual(code, 1)
        self.assertIn("1 .swift + 1 .json5 family files: 2, but", output)
        (self.goldens / "aa-swift.txt").write_text("golden\n")
        self.assertEqual(self.main()[0], 0)
        (self.goldens / "zz-extra.txt").write_text("golden\n")
        self.assertEqual(self.main()[0], 1)
        shutil.rmtree(self.goldens)
        code, output = self.main()
        self.assertEqual(code, 1)
        self.assertIn("cannot be reconciled", output)

    # Mutation: `files < minimum` becomes `<=`.
    def test_the_floor_admits_exactly_the_minimum(self):
        self.write("zz-fixture.json5", VALID)
        self.assertEqual(self.main(minimum=1)[0], 0)

    # Mutation: `main` returns 0 while `review` reports a problem, or skips files
    # after the first.
    def test_a_problem_in_any_file_fails_main_and_names_it(self):
        self.write("aa-fixture.json5", VALID)
        self.write("zz-fixture.json5", VALID.replace('"kind": "zip"', '"kind": "zip",'))
        code, output = self.main()
        self.assertEqual(code, 1)
        self.assertIn("zz-fixture.json5:15:", output)
        self.assertIn("[trailing-comma]", output)

    # Mutation: delete the success print.
    def test_a_clean_tree_passes(self):
        self.write("zz-fixture.json5", VALID)
        code, output = self.main()
        self.assertEqual(code, 0)
        self.assertIn("✓ recipe .json5 files in dialect, no duplicate keys — 1 files; "
                      "family files reconcile with 1 goldens", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)

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

    # Mutation: stop blanking whole-line comments before json.loads (every file
    # with a comment fails), or blank a line that has code before `//`.
    def test_anything_else_outside_json_fails_json_loads(self):
        self.assertEqual(kinds(VALID.replace('"maxEntries": 1e2', '"maxEntries": 0x1F')), ["not-json"])
        self.assertEqual(kinds(VALID.replace('"maxEntries": 1e2', '"maxEntries": +1')), ["not-json"])


class Tree(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="duo-json5-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.data = self.root / crj.RECIPE_DATA
        self.data.mkdir(parents=True)

    def write(self, name, text):
        (self.data / name).write_text(text)

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
        self.write("zz-fixture.json", VALID)  # wrong extension: not a family file
        code, output = self.main()
        self.assertEqual(code, 1)
        self.assertIn("only 0 recipe .json5 files", output)

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
        self.assertIn("✓ recipe .json5 files in dialect, no duplicate keys — 1 files", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)

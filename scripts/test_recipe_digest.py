#!/usr/bin/env python3
"""Regression tests for `recipe_digest`. Run by `make test`.

    python3 scripts/test_recipe_digest.py

The known answer is shared with `AppRecipeIndexTests.theRecipeDigestHasOneKnownAnswer`
(Swift, `RecipeFamilyFile.digest`). It was also computed a third way, by piping
the framed bytes to `shasum -a 256`. If either implementation changes its framing,
its own test goes red; changing both together means changing both constants,
which is a decision rather than drift.
"""

import contextlib
import io
import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import recipe_digest as rd  # noqa: E402

KNOWN_ANSWER = "8fdc639d4711a2edc32eb757828c6e2b89c5c98a7c10051cd1242814a11a8692"


class Digest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="duo-digest-"))
        self.addCleanup(shutil.rmtree, self.dir, True)
        # Written in reverse order, so directory order is not name order by luck.
        (self.dir / "b-app.json5").write_bytes(b'// c\n{"probes": []}\n')
        (self.dir / "a-app.json5").write_bytes(b"{}\n")

    # Mutations: drop the name, the length or the sort from the framing; hash
    # with anything but SHA-256.
    def test_the_known_answer(self):
        self.assertEqual(rd.digest(self.dir), (KNOWN_ANSWER, None))

    # Mutation: hash contents only (a rename would keep the digest).
    def test_a_rename_moves_the_digest(self):
        (self.dir / "a-app.json5").rename(self.dir / "c-app.json5")
        self.assertNotEqual(rd.digest(self.dir)[0], KNOWN_ANSWER)

    # Mutation: drop the length (bytes re-split across two files would collide).
    def test_moving_bytes_between_files_moves_the_digest(self):
        (self.dir / "a-app.json5").write_bytes(b"{}\n// c\n")
        (self.dir / "b-app.json5").write_bytes(b'{"probes": []}\n')
        self.assertNotEqual(rd.digest(self.dir)[0], KNOWN_ANSWER)

    # Mutation: skip entries that are not family files instead of refusing.
    def test_a_directory_the_loader_would_refuse_has_no_digest(self):
        (self.dir / ".DS_Store").write_bytes(b"x")
        value, problem = rd.digest(self.dir)
        self.assertIsNone(value)
        self.assertIn(".DS_Store", problem)

    def test_an_empty_or_missing_directory_has_no_digest(self):
        for path in (self.dir / "b-app.json5", self.dir / "a-app.json5"):
            path.unlink()
        self.assertEqual(rd.digest(self.dir)[0], None)
        self.assertEqual(rd.digest(self.dir / "nope")[0], None)

    # Mutation: `main` exits 0 without printing, or prints on failure.
    def test_main_prints_the_digest_or_fails(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(rd.main([str(self.dir)]), 0)
        self.assertEqual(out.getvalue(), KNOWN_ANSWER + "\n")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(rd.main([str(self.dir / "nope")]), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)

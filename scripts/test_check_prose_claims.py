#!/usr/bin/env python3
"""Regression tests for `check_prose_claims`. Run by `make test`.

    python3 scripts/test_check_prose_claims.py

Every case names the mutation it catches. The must-hit fixture is the real
sentence that motivated the check, copied verbatim from 38596f7 — including its
line wrapping, which is the part a `grep` cannot see.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_prose_claims as cpc  # noqa: E402

# Verbatim from 38596f7, wrapped exactly as it was committed. The wrap is the
# fixture: "1 of the 22 store" ends one line and "apps on this machine" begins
# the next, so a line-based scanner sees neither half.
INSTANCE_3 = """\
    /// and `SparkleAppcastSource` (feed-url gate only — measured 2026-08-29, Keka
    /// is a store copy carrying `SUFeedURL = https://u.keka.io`, 1 of the 22 store
    /// apps on this machine).
    @Test func witness() {}
"""

# Real comments from this repo that the check must leave alone.
LEGITIMATE = """\
    /// …but only against a version this recipe is FOR. A recipe scoped to an
    /// older train legitimately trails the installed copy: the machine running
    /// the sweep is on 2.0.6.0, and `versions` only ever holds what is installed
    /// here.
    ///
    /// One-click verified on this machine 2026-08-09 on 1.9.3: `ImageOptim.app`
    /// in the archive, bundle id net.pornel.ImageOptim, Team 59KZTZA4XR.
    ///
    /// `selectHighest` rather than first-match, because the feed is ASCENDING
    /// (8.7.0 from 2022 is item 1 of 89) — first-match here would report a
    /// four-year-old release as current.
    func f() {}
"""


class ProseClaims(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="duo-claims-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "Sources").mkdir()

    def write(self, text, name="Fixture.swift"):
        (self.root / "Sources" / name).write_text(text)

    def review(self):
        return cpc.review(self.root, roots=["Sources"])

    # Mutation: drop the line-joining in `comment_blocks` and scan line by line.
    # This is the whole reason the check is a script — the sentence it exists for
    # wraps, so a per-line scanner reports zero and ships green forever.
    def test_the_wrapped_sentence_that_motivated_this_is_caught(self):
        self.write(INSTANCE_3)
        found = self.review()
        self.assertEqual(len(found["offences"]), 1, found)
        self.assertIn("1 of the 22 store apps on this machine",
                      found["offences"][0][2])

    # The same claim on one line. Both must hit, or the check would reward
    # reflowing a comment.
    def test_the_same_sentence_unwrapped_is_caught_too(self):
        self.write("    /// Keka is a store copy, 1 of the 22 store apps on this "
                   "machine.\n    func f() {}\n")
        self.assertEqual(len(self.review()["offences"]), 1)

    # Mutation: widen PATTERN back to a bare "this machine", or re-add the
    # `installed here` alternative. Both of these are real comments from this
    # repo and both would start failing — the direction that turns the check into
    # an exemption list.
    # Three real comments from this repo, all of which an earlier version of the
    # pattern matched: a dated verification of an artifact anyone holding it can
    # redo, a "here" that means "in this code", and a count of a FEED's 89 items
    # that a 90-character window bridged to an unrelated "here".
    def test_a_dated_verification_and_a_runtime_here_are_left_alone(self):
        self.write(LEGITIMATE)
        found = self.review()
        self.assertEqual(found["offences"], [], found)
        self.assertEqual(found["dead"], [])

    # Mutation: stop honouring MARKER at all.
    def test_an_exemption_with_a_reason_clears_it(self):
        self.write("    /// 1 of the 22 store apps on this machine.\n"
                   "    /// claim-lint:allow-machine-state — the count IS the "
                   "measurement here\n    func f() {}\n")
        self.assertEqual(self.review()["offences"], [])

    # Mutation: drop the REASON check and accept a bare marker. An escape hatch
    # that takes no argument is a way to turn the check off — the same reason
    # `version-lint:allow-marketing-first` demands one.
    def test_a_bare_exemption_is_not_an_exemption(self):
        self.write("    /// 1 of the 22 store apps on this machine.\n"
                   "    /// claim-lint:allow-machine-state\n    func f() {}\n")
        found = self.review()
        self.assertEqual(len(found["offences"]), 1)
        self.assertIn("no reason", found["offences"][0][2])

    # Mutation: delete the `elif exempt and not match` branch. A marker left
    # behind after its sentence was rewritten is a standing pass for whatever is
    # written there next — #271 is what that costs.
    def test_an_exemption_matching_nothing_fails(self):
        self.write("    /// Nothing measurable here at all.\n"
                   "    /// claim-lint:allow-machine-state — stale\n"
                   "    func f() {}\n")
        found = self.review()
        self.assertEqual(len(found["dead"]), 1, found)

    # Mutation: `continue` past a missing root instead of reporting it. The very
    # first run of the check printed "✓ … 0 roots scanned" and exited 0.
    def test_a_missing_root_is_a_failure_not_a_smaller_scan(self):
        self.write(INSTANCE_3)
        self.assertEqual(cpc.review(self.root, roots=["Nope"])["missing"], ["Nope"])
        # `roots` passed explicitly: without it `main` reads the module-level
        # ROOTS, which a temp directory never has, so this case went red for a
        # reason that had nothing to do with what it names. It was written that
        # way first and only the clean-tree case below exposed it.
        self.assertEqual(cpc.main(root=self.root, roots=["Nope"], minimum=1), 1)

    # Mutation: delete the floor. A root that exists but holds no Swift is just
    # as silent as one that is gone.
    def test_scanning_almost_nothing_is_a_failure(self):
        self.write(INSTANCE_3)
        self.assertEqual(cpc.main(root=self.root, roots=["Sources"], minimum=10_000), 1)

    # The check's own exit code, end to end, on a clean fixture.
    def test_a_clean_tree_passes(self):
        self.write(LEGITIMATE)
        self.assertEqual(cpc.main(root=self.root, roots=["Sources"], minimum=1), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)

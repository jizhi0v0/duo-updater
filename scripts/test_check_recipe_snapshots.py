#!/usr/bin/env python3
"""Regression tests for `check_recipe_snapshots`. Run by `make test`.

    python3 scripts/test_check_recipe_snapshots.py

Every case names the mutation it catches. The must-hit fixtures are the real
comment lines from #607, #610, #622 and #623 as they stood at 2370b8ac, trimmed to
the paragraph but with their line wrapping, which a line scanner cannot see.
"""

import pathlib
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_recipe_snapshots as crs  # noqa: E402

# Verbatim from `com-windscribe-client.swift` (#607). The observation verb ends
# the first line and the date and counts start the second, so neither line alone
# matches any shape.
WRAPPED = """\
        // ⚠️ WHAT THIS LISTS THAT IT SHOULD NOT, measured on the newest 40
        // releases (2026-09-07): 9 are stable and 31 are prereleases, and GitHub
        // marks all 31 the same way — it has no idea which track a build is on.
"""

# Verbatim from #610, #623 and #622, one paragraph each, with the shape
# each must be reported under.
REAL = {
    "dated-narrative": """\
        // offer, and to the plain stable zip between cycles — measured, not
        // "likely": 2026-09-14 it answered with the same `ccc-7.2.8399.zip` as
        // `?v=ccc7` and `?v=latest`. `versionPattern` accepts BOTH, which is why
""",
    "count-on-date": """\
        // Shape (51 entries on 2026-09-14): `## v1.0.914.1` headings from 1.0.626.1
        // up, bare `## 1.0.624.1` below that.
""",
    "measurement-led": """\
        // the patterns are the same three strings; only `source` and the version
        // window differ. Verified against the live page 2026-09-14: 10 entries,
        // 1.104.0 back to 1.95.0, all parsing.
""",
}
ASIDE_NARRATIVE = """\
        // livecheck reads. It carries one object per PLATFORM, and the platforms do
        // not ship together: on 2026-09-14 it said mac `1.0.910.1` and win
        // `1.0.914.1`, and the changelog page already led with 914.1. So both
"""

# The shapes the migration batches keep in code, as real comments (trimmed).
ALLOWED = """\
        // Both answer any client the same way regardless of the UA's OS/architecture
        // (measured 2026-08-27 across Intel/Sequoia/ browser agents), which is why.
        //
        // The zip's own key does verify that item's signature over the payload
        // (Ed25519, checked 2026-09-04), but note what that is and is not.
        //
        // It is a JS shell that fetches this same file client-side (measured
        // 2026-08-29 — the served HTML does not contain any release-note string).
        //
        // `plan_type` is the second thing the endpoint keys on, and unlike
        // `app_version` it decides the answer. Measured 2026-08-24 (History has
        // the table), the consumer values (`free`, `go`, `plus`, `pro`, `team`)
        // resolved to a newer build than `business`, `enterprise` and `ent26`.
        //
        // A few versions appear TWICE on the page (when checked, 2026-09-14: 3.10.23,
        // 3.10.22 and 3.9.2 repeat), and for two of those the bodies differ.
        //
        // The vendor's JSON update check states the build as a bare number
        // (`"latest_version": 4200` when checked 2026-09-14), not "Build NNNN".
        //
        // Each item (captured verbatim 2026-08-16):
        //
        // `changelogs.dev` holds exactly one entry — and it is fixture data
        // (verified 2026-08-09):
        //   "v0.2026.08.07.08.31.dev_00": { "date": "2021-11-23T10:07:01-06:00",
        //     "sections": [ { "title": "dev", "items": ["dev 1", "dev 2"] } ] }
        //
        // The regression tests use those dates: on 2026-08-01 the three answer
        // 2.23.11 / 2.23.11 / 2.24.6, and on 2026-08-12 they answer 2.23.11 /
        // 2.24.8 / 2.24.8.
        //
        // MARK: - 2026-09-12 Cline Desktop
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        //
        // A `-preview.` release series has also appeared (tags since 2026-09-12,
        // releases since 2026-09-13) and is not covered.
"""

POINTER = "        // History: docs/app-audits/{family}.md#历史与实测\n"
TEMP = "        // snapshot-lint:allow — catch-up batch after 2f\n"


def swift(comment):
    return comment + "        VendorProbeRecipe()\n"


class Snapshots(unittest.TestCase):
    def setUp(self):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="duo-snapshots-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.recipes = self.root / crs.RECIPES
        self.recipes.mkdir(parents=True)

    def write(self, family, text):
        (self.recipes / f"{family}.swift").write_text(text)

    def review(self, pending=frozenset(), last="aa-0", out_of_order=None, shapes=None):
        return crs.review(self.root, pending=pending, last_migrated=last,
                          out_of_order=out_of_order or {}, shapes=shapes)

    def kinds(self, found):
        return [kind for _, _, kind, _ in found["offences"]]

    # Floor fixture for the PENDING checks: `last` must name a real family.
    def anchor(self):
        self.write("aa-0", swift("        // nothing dated here.\n"))

    # Mutation: scan line by line instead of joining the paragraph.
    def test_a_sentence_wrapped_across_lines_is_caught(self):
        self.anchor()
        self.write("zz-windscribe", swift(WRAPPED))
        self.assertEqual(self.kinds(self.review()), ["observed-then-values"])

    # Mutation: delete or break the shape named in each sub-case.
    def test_the_real_snapshots_from_610_622_623_are_caught_under_their_shape(self):
        self.anchor()
        for shape, comment in REAL.items():
            with self.subTest(shape=shape):
                self.write("zz-fixture", swift(comment))
                self.assertEqual(self.kinds(self.review()), [shape])
        self.write("zz-fixture", swift(ASIDE_NARRATIVE))
        self.assertEqual(self.kinds(self.review()), ["dated-narrative"])

    # Mutation: delete `date-led` or `as-of` (no real instance left in a guarded
    # family, so these are synthetic).
    def test_date_led_and_as_of_are_caught(self):
        self.anchor()
        for shape, comment in {
                "date-led": "        // 2026-08-09: the bare `/changelog` root is NOT "
                            "this app's changelog.\n",
                "as-of": "        // The v1 train is still shipping as of 2026-08-18.\n"}.items():
            with self.subTest(shape=shape):
                self.write("zz-fixture", swift(comment))
                self.assertEqual(self.kinds(self.review()), [shape])

    # Mutations: drop the History-reference exclusion, WHEN_CHECKED, the value
    # requirement, or the indented-excerpt break; widen `dated-narrative`
    # to any verb. Each turns one paragraph of this real-shaped fixture red.
    def test_the_shapes_the_batches_keep_are_left_alone(self):
        self.anchor()
        self.write("zz-fixture", POINTER.format(family="zz-fixture") + swift(ALLOWED))
        found = self.review()
        self.assertEqual(found["offences"], [], found)
        self.assertEqual(found["stale"], [])

    # Mutation: check PENDING families too, or skip families not in PENDING.
    def test_a_pending_family_is_skipped_and_a_new_family_is_guarded(self):
        self.anchor()
        self.write("zz-pending", swift(REAL["count-on-date"]))
        self.write("zz-new", swift(REAL["count-on-date"]))
        found = self.review(pending=frozenset({"zz-pending"}))
        self.assertEqual([rel.stem for rel, _, _, _ in found["offences"]], ["zz-new"])
        self.assertEqual((found["guarded"], found["pending"]), (2, 1))

    # Mutation: skip a PENDING slug that names no file.
    def test_pending_naming_no_family_is_a_problem(self):
        self.anchor()
        found = self.review(pending=frozenset({"zz-gone"}))
        self.assertEqual(len(found["pending_problems"]), 1, found)
        self.assertIn("names no family", found["pending_problems"][0])

    # Mutation: delete the "already has a History pointer" check.
    def test_pending_family_with_a_pointer_is_a_problem(self):
        self.anchor()
        self.write("zz-done", POINTER.format(family="zz-done") + swift("        // ok.\n"))
        found = self.review(pending=frozenset({"zz-done"}))
        self.assertIn("already has a History pointer", " ".join(found["pending_problems"]))

    # Mutation: delete the LAST_MIGRATED comparison, or let OUT_OF_ORDER entries
    # go stale silently.
    def test_pending_inside_the_migrated_range_is_a_problem_unless_recorded(self):
        self.write("bb-last", swift("        // ok.\n"))
        self.write("aa-skipped", swift("        // ok.\n"))
        found = self.review(pending=frozenset({"aa-skipped"}), last="bb-last")
        self.assertIn("sorts inside the migrated range", " ".join(found["pending_problems"]))
        found = self.review(pending=frozenset({"aa-skipped"}), last="bb-last",
                            out_of_order={"aa-skipped": "skipped"})
        self.assertEqual(found["pending_problems"], [])
        found = self.review(pending=frozenset(), last="bb-last",
                            out_of_order={"aa-skipped": "skipped"})
        self.assertIn("no longer applies", " ".join(found["pending_problems"]))

    # Mutation: let LAST_MIGRATED name a missing family.
    def test_last_migrated_must_name_a_family(self):
        self.anchor()
        found = self.review(last="zz-nope")
        self.assertIn("names no family", " ".join(found["pending_problems"]))

    # Mutation: stop honouring MARKER.
    def test_a_marker_with_a_reason_clears_its_paragraph(self):
        self.anchor()
        self.write("zz-fixture", swift(REAL["measurement-led"] + TEMP))
        found = self.review()
        self.assertEqual((found["offences"], found["stale"]), ([], []))

    # Mutation: accept a bare marker.
    def test_a_bare_marker_is_not_an_exemption(self):
        self.anchor()
        self.write("zz-fixture", swift(REAL["measurement-led"]
                                       + "        // snapshot-lint:allow\n"))
        # The snapshot stays reported next to the bare marker.
        self.assertEqual(sorted(self.kinds(self.review())), ["measurement-led", "no-reason"])

    # Mutation: scope a marker to the whole comment block instead of its paragraph.
    def test_a_marker_does_not_reach_the_next_paragraph(self):
        self.anchor()
        self.write("zz-fixture", swift(REAL["count-on-date"] + TEMP + "        //\n"
                                       + REAL["measurement-led"]))
        found = self.review()
        self.assertEqual(self.kinds(found), ["measurement-led"], found)

    # Mutation: accept the marker anywhere on a line. Describing the convention
    # would then read as invoking it and be reported as a stale exemption.
    def test_describing_the_marker_is_not_invoking_it(self):
        self.anchor()
        self.write("zz-fixture", swift("        // Exempt with a `snapshot-lint:allow — "
                                       "<reason>` line.\n"))
        found = self.review()
        self.assertEqual((found["offences"], found["stale"]), ([], []))

    # Mutation: delete the stale-marker branch.
    def test_a_marker_whose_paragraph_has_no_snapshot_fails(self):
        self.anchor()
        self.write("zz-fixture", swift("        // Nothing dated here.\n" + TEMP))
        self.assertEqual(len(self.review()["stale"]), 1)

    # Mutation: delete the history-without-pointer check. "History has …" exempts
    # a sentence; in a family with no History it would be a free pass.
    def test_citing_history_without_a_pointer_fails(self):
        self.anchor()
        self.write("zz-fixture", swift("        // It answered 1.2.3 on the day "
                                       "(verified 2026-09-14; History has the check).\n"))
        self.assertEqual(self.kinds(self.review()), ["history-without-pointer"])

    # Mutation: `return found` without reporting a missing Recipes directory.
    def test_a_missing_recipes_dir_is_a_failure(self):
        empty = pathlib.Path(tempfile.mkdtemp(prefix="duo-snapshots-empty-"))
        self.addCleanup(shutil.rmtree, empty, True)
        self.assertEqual(crs.main(root=empty, pending=frozenset(), last_migrated="x",
                                  out_of_order={}, minimum=0), 1)

    # Mutation: delete the guarded-family floor.
    def test_guarding_too_few_families_is_a_failure(self):
        self.anchor()
        self.assertEqual(crs.main(root=self.root, pending=frozenset(), last_migrated="aa-0",
                                  out_of_order={}, minimum=10), 1)

    # Mutation: delete the canary check in `main`. A shape that stops matching
    # then fails nothing on a tree whose snapshots are all exempted.
    def test_a_broken_shape_fails_the_canaries(self):
        self.anchor()
        broken = dict(crs.SHAPES)
        broken["count-on-date"] = (crs.re.compile(r"(?!x)x"), False)
        self.assertTrue(crs.canary_problems(broken))
        self.assertEqual(crs.main(root=self.root, pending=frozenset(), last_migrated="aa-0",
                                  out_of_order={}, minimum=1, shapes=broken), 1)

    # The check's own exit code, end to end, on a clean fixture.
    def test_a_clean_tree_passes(self):
        self.anchor()
        self.write("zz-fixture", POINTER.format(family="zz-fixture") + swift(ALLOWED))
        self.assertEqual(crs.main(root=self.root, pending=frozenset(), last_migrated="aa-0",
                                  out_of_order={}, minimum=1), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)

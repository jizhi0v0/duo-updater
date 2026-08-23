#!/usr/bin/env python3
"""Regression tests for `appcast_edit`.

Every case here is a shape that reached the real feed or was one plausible
vendor/tooling change away from it. Run by `make test` and by
`publish-release.sh` itself, so a release cannot go out over a red suite.

    python3 scripts/test_appcast_edit.py
"""

import sys
import pathlib
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import appcast_edit as ae  # noqa: E402


def item(version, build, tag="item", notes="notes", length=1234, min_os="14.0"):
    return (
        f"        <{tag}>\n"
        f"            <title>{version}</title>\n"
        f"            <sparkle:version>{build}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"            <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>\n"
        f"            <description><![CDATA[{notes}]]></description>\n"
        f'            <enclosure url="https://example/{version}.zip" length="{length}"/>\n'
        f"        </item>\n"
    )


def feed(*items, channels=1, channel_tag="channel"):
    body = "".join(items)
    inner = "".join(f"    <{channel_tag}>\n        <title>Duo</title>\n{body}    </channel>\n"
                    for _ in range(channels))
    return (
        '<?xml version="1.0"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        f"{inner}</rss>\n")


THREE = feed(item("0.3.53", "62"), item("0.3.52", "61"), item("0.3.51", "60"))


class StripItem(unittest.TestCase):
    def test_removes_the_newest_and_keeps_the_rest(self):
        out = ae.strip_item(THREE, "62", "0.3.53")
        self.assertEqual(ae.short_versions(out), ["0.3.52", "0.3.51"])

    def test_removes_the_oldest_without_emptying_the_feed(self):
        """The failure that motivated splitting into whole items: a lazy prefix
        starting at the first item swallowed everything before the target."""
        out = ae.strip_item(THREE, "60", "0.3.51")
        self.assertEqual(ae.short_versions(out), ["0.3.53", "0.3.52"])

    def test_removes_the_middle(self):
        out = ae.strip_item(THREE, "61", "0.3.52")
        self.assertEqual(ae.short_versions(out), ["0.3.53", "0.3.51"])

    def test_matches_an_item_carrying_attributes(self):
        """`<item>` matched literally is a silent no-op on this feed — and a
        no-op strip does not fail, it publishes the version twice."""
        attributed = feed(
            item("0.3.53", "62", tag='item xmlns:sparkle="http://x"'),
            item("0.3.52", "61"))
        out = ae.strip_item(attributed, "62", "0.3.53")
        self.assertEqual(ae.short_versions(out), ["0.3.52"])

    def test_release_notes_containing_a_closing_item_tag_do_not_tear_the_feed(self):
        """The notes are prose lifted from CHANGELOG.md and can contain anything."""
        tricky = feed(
            item("0.3.53", "62", notes="talks about </item> in passing"),
            item("0.3.52", "61"))
        out = ae.strip_item(tricky, "62", "0.3.53")
        self.assertEqual(ae.short_versions(out), ["0.3.52"])
        # The weaker assertion above passes even when the item is torn in half,
        # because the half carrying the version string is the half that goes.
        # What actually distinguishes a clean removal is that the document still
        # parses and has exactly the one item left.
        root = ET.fromstring(out)
        self.assertEqual(len(root.findall(".//item")), 1)

    def test_a_version_tag_quoted_inside_release_notes_is_not_a_match(self):
        quoted = feed(
            item("0.3.53", "62",
                 notes="the feed said <sparkle:version>60</sparkle:version> here"),
            item("0.3.51", "60"))
        out = ae.strip_item(quoted, "60", "0.3.51")
        self.assertEqual(ae.short_versions(out), ["0.3.53"])

    def test_crlf_line_endings(self):
        out = ae.strip_item(THREE.replace("\n", "\r\n"), "62", "0.3.53")
        self.assertEqual(ae.short_versions(out), ["0.3.52", "0.3.51"])

    def test_a_version_not_in_the_feed_changes_nothing(self):
        self.assertEqual(ae.strip_item(THREE, "99", "0.9.9"), THREE)

    def test_a_self_closing_item_is_left_alone(self):
        with_empty = THREE.replace("    </channel>", "        <item/>\n    </channel>")
        out = ae.strip_item(with_empty, "62", "0.3.53")
        self.assertIn("<item/>", out)
        self.assertEqual(ae.short_versions(out), ["0.3.52", "0.3.51"])

    def test_matching_on_the_short_version_alone_also_works(self):
        out = ae.strip_item(THREE, "999", "0.3.52")
        self.assertEqual(ae.short_versions(out), ["0.3.53", "0.3.51"])


class ChannelCount(unittest.TestCase):
    def test_single_channel(self):
        self.assertEqual(ae.channel_count(THREE), 1)

    def test_a_second_channel_is_visible_to_the_caller(self):
        """`strip_item` deletes from every channel while `generate_appcast`
        regenerates one, so the caller must refuse rather than proceed."""
        self.assertEqual(ae.channel_count(feed(item("0.3.53", "62"), channels=2)), 2)


class DuplicateAndEnclosure(unittest.TestCase):
    def test_one_item_per_build_normally(self):
        self.assertEqual(len(ae.items_for_build(THREE, "62")), 1)

    def test_a_no_op_strip_shows_up_as_two_items_for_one_build(self):
        self.assertEqual(
            len(ae.items_for_build(feed(item("0.3.53", "62"), item("0.3.53", "62")), "62")), 2)

    def test_enclosure_length_is_read_from_the_right_item(self):
        self.assertEqual(ae.enclosure_length(THREE, "61"), 1234)

    def test_enclosure_length_is_none_when_the_build_is_absent(self):
        self.assertIsNone(ae.enclosure_length(THREE, "99"))


class CheckRegenerated(unittest.TestCase):
    """The gate `publish-release.sh` runs on the feed `generate_appcast` produced.

    Every REFUSE case below is a way the feed has actually gone wrong, or the
    same shape one step along: 0.3.50 vanished when the strip swallowed an extra
    item, 0.3.49 rolled off while a count-only check called it normal.
    """

    CAP = 5
    SIZE = 1234

    def check(self, old, new, want, build, size=None, cap=None):
        return ae.check_regenerated(old, new, want, build,
                                    self.SIZE if size is None else size,
                                    self.CAP if cap is None else cap)

    def setUp(self):
        self.three = THREE
        self.plus54 = feed(item("0.3.54", "63"), item("0.3.53", "62"),
                           item("0.3.52", "61"), item("0.3.51", "60"))

    # --- publishable -----------------------------------------------------
    def test_a_normal_addition(self):
        self.assertEqual(self.check(self.three, self.plus54, "0.3.54", "63"), [])

    def test_the_oldest_rolling_off_a_full_window(self):
        full = feed(*[item(f"0.3.{n}", str(n)) for n in (57, 56, 55, 54, 53)])
        rolled = feed(*[item(f"0.3.{n}", str(n)) for n in (58, 57, 56, 55, 54)])
        self.assertEqual(self.check(full, rolled, "0.3.58", "58"), [])

    def test_reissuing_the_same_version(self):
        self.assertEqual(self.check(self.three, self.three, "0.3.53", "62"), [])

    def test_the_first_publish_into_an_empty_feed(self):
        self.assertEqual(self.check("", feed(item("0.3.1", "1")), "0.3.1", "1"), [])

    # --- refused ---------------------------------------------------------
    def test_the_newest_entry_vanishing(self):
        """0.3.50, 2026-08-22: the strip's lazy prefix ate the item before it."""
        lost = feed(item("0.3.54", "63"), item("0.3.52", "61"), item("0.3.51", "60"))
        self.assertTrue(self.check(self.three, lost, "0.3.54", "63"))

    def test_an_entry_vanishing_from_the_middle(self):
        lost = feed(item("0.3.54", "63"), item("0.3.53", "62"), item("0.3.51", "60"))
        self.assertTrue(self.check(self.three, lost, "0.3.54", "63"))

    def test_the_feed_emptied_down_to_the_new_entry(self):
        self.assertTrue(self.check(self.three, feed(item("0.3.54", "63")), "0.3.54", "63"))

    def test_a_one_entry_feed_losing_its_only_entry(self):
        """Trivially "one lost, and it is the oldest" — which is why the count
        has to be exact rather than merely suffix-shaped."""
        one = feed(item("0.3.53", "62"))
        self.assertTrue(self.check(one, feed(item("0.3.54", "63")), "0.3.54", "63"))

    def test_the_new_version_missing_altogether(self):
        self.assertTrue(self.check(self.three, self.three, "0.3.54", "63"))

    def test_two_items_for_one_build(self):
        """What a no-op strip produces: the old item survives and a second is
        added. No entry is lost, so a loss-only check sees nothing."""
        dup = feed(item("0.3.54", "63"), item("0.3.54", "63"),
                   item("0.3.53", "62"), item("0.3.52", "61"))
        problems = self.check(self.three, dup, "0.3.54", "63")
        self.assertTrue(any("2 items for build 63" in p for p in problems))

    def test_an_enclosure_length_that_does_not_match_the_artifact(self):
        """The surviving old item keeps the previous binary's length and EdDSA
        signature while the release now serves different bytes."""
        stale = feed(item("0.3.54", "63", length=999), item("0.3.53", "62"),
                     item("0.3.52", "61"), item("0.3.51", "60"))
        problems = self.check(self.three, stale, "0.3.54", "63")
        self.assertTrue(any("999 bytes" in p for p in problems))


class ChecksThatWereNotPinned(unittest.TestCase):
    """Cases isolating checks that a mutation run showed were carried by a
    *different* check than their name suggested. Each one is constructed so that
    only the named check can refuse it."""

    CAP = 5
    SIZE = 1234

    def check(self, old, new, want, build):
        return ae.check_regenerated(old, new, want, build, self.SIZE, self.CAP)

    def test_a_middle_loss_hidden_behind_a_correct_entry_count(self):
        """0.3.52 vanishes while an unrelated entry appears, so the count still
        lands on `expected` and only the suffix rule can catch it."""
        new = feed(item("0.3.54", "63"), item("0.3.53", "62"),
                   item("0.3.51", "60"), item("0.3.50", "59"))
        problems = self.check(THREE, new, "0.3.54", "63")
        self.assertTrue(any("from the middle" in p for p in problems), problems)

    def test_the_wanted_marketing_version_absent_while_its_build_is_present(self):
        """Publishing 0.3.54 but the feed only ever says 0.3.53 for that build.
        The duplicate check is satisfied, so `want not in new` stands alone."""
        problems = self.check(THREE, THREE, "0.3.54", "62")
        self.assertTrue(any("does not contain 0.3.54" in p for p in problems), problems)

    def test_a_channel_carrying_attributes_is_still_a_channel(self):
        """`<channel>` matched literally would report 1 channel for a two-channel
        feed and let `strip_item` gut the one generate_appcast does not rewrite."""
        two = feed(item("0.3.53", "62"), channels=2,
                   channel_tag='channel xmlns:sparkle="http://x"')
        self.assertEqual(ae.channel_count(two), 2)

    def test_release_notes_mentioning_a_channel_tag_do_not_look_like_one(self):
        """The notes live in the PUBLISHED feed, so a false positive here blocks
        every future release until someone hand-edits the appcast."""
        tricky = feed(item("0.3.53", "62", notes="we dropped the <channel> element"))
        self.assertEqual(ae.channel_count(tricky), 1)

    def test_one_marketing_version_under_two_builds_keeps_its_identity(self):
        """Entries keyed on the marketing string alone made losing one of a
        same-version pair invisible."""
        old = feed(item("0.3.53", "63"), item("0.3.53", "62"),
                   item("0.3.52", "61"), item("0.3.51", "60"))
        # 0.3.53/62 vanishes from the middle; 0.3.53 is still "present".
        new = feed(item("0.3.54", "64"), item("0.3.53", "63"),
                   item("0.3.52", "61"), item("0.3.51", "60"))
        self.assertTrue(self.check(old, new, "0.3.54", "64"))

    def test_a_second_minimum_os_stops_rather_than_misreports(self):
        """`--maximum-versions` caps per branch point, so the single-window count
        stops describing generate_appcast the moment a second one exists."""
        old = feed(item("0.3.53", "62"), item("0.3.52", "61"))
        new = feed(item("0.3.54", "63", min_os="15.0"), item("0.3.53", "62"),
                   item("0.3.52", "61"))
        problems = self.check(old, new, "0.3.54", "63")
        self.assertTrue(any("branch points" in p for p in problems), problems)


class EmbeddedPythonCompiles(unittest.TestCase):
    """`publish-release.sh` carries its remaining logic in `python3 - <<'PY'`
    heredocs, and **`bash -n` cannot see inside them** — a Python syntax error
    there passes the shell syntax check and only surfaces when that gate runs,
    mid-release. (Measured: an unterminated f-string in the build-number check
    passed `bash -n` and failed at publish time.)"""

    def test_every_heredoc_in_publish_release_is_valid_python(self):
        script = pathlib.Path(__file__).resolve().parent / "publish-release.sh"
        lines = script.read_text().split("\n")
        blocks, current = [], None
        for line in lines:
            if current is not None:
                if line.strip() == "PY":
                    blocks.append("\n".join(current))
                    current = None
                else:
                    current.append(line)
            elif "python3 - <<'PY'" in line:
                current = []
        self.assertIsNone(current, "a PY heredoc is never closed")
        self.assertGreaterEqual(len(blocks), 4, f"only found {len(blocks)} heredocs — did the shape change?")
        for i, block in enumerate(blocks):
            with self.subTest(block=i):
                compile(block, f"<publish-release.sh heredoc {i}>", "exec")



def signed_item(version, build, signature, deltas=(), length=1234):
    """An item whose archive carries an EdDSA signature, optionally with patches
    nested in `<sparkle:deltas>` — the shape `generate_appcast` writes once past
    archives are present in its working directory."""
    delta_block = ""
    if deltas:
        rows = "".join(
            f'                <enclosure url="https://example/{build}-{frm}.delta"'
            f' sparkle:deltaFrom="{frm}" length="4096"'
            f' sparkle:edSignature="{sig}"/>\n'
            for frm, sig in deltas)
        delta_block = f"            <sparkle:deltas>\n{rows}            </sparkle:deltas>\n"
    return (
        "        <item>\n"
        f"            <title>{version}</title>\n"
        f"            <sparkle:version>{build}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n"
        f'            <enclosure url="https://example/{version}.zip" length="{length}"'
        f' sparkle:edSignature="{signature}"/>\n'
        f"{delta_block}"
        "        </item>\n"
    )


class ArchiveSignatureTests(unittest.TestCase):
    """Publishing with history present makes `generate_appcast` rewrite items that
    are already public. These guard the one way that can go wrong."""

    def test_reads_the_archive_signature_not_a_patchs(self):
        text = feed(signed_item("0.3.61", "70", "ARCHIVE",
                                deltas=[("69", "PATCH69"), ("68", "PATCH68")]))
        self.assertEqual(ae.archive_signatures(text), {("0.3.61", "70"): "ARCHIVE"})

    def test_a_rebuilt_archive_is_refused(self):
        # Same version, different bytes: the feed would advertise a proof that
        # does not match what the release serves, and every existing user's
        # update fails verification.
        old = feed(signed_item("0.3.60", "69", "ORIGINAL"))
        new = feed(signed_item("0.3.60", "69", "REBUILT"))
        problems = ae.check_signatures_unchanged(old, new)
        self.assertEqual(len(problems), 1)
        self.assertIn("0.3.60", problems[0])
        self.assertIn("already published", problems[0])

    def test_an_unchanged_archive_passes(self):
        old = feed(signed_item("0.3.60", "69", "SAME"))
        new = feed(signed_item("0.3.60", "69", "SAME"), )
        self.assertEqual(ae.check_signatures_unchanged(old, new), [])

    def test_gaining_patches_is_not_a_change(self):
        # The whole point of the change: an item that gains `<sparkle:deltas>`
        # while its archive signature stays put is an ordinary, correct publish.
        old = feed(signed_item("0.3.60", "69", "SAME"))
        new = feed(signed_item("0.3.60", "69", "SAME",
                               deltas=[("68", "P68"), ("67", "P67")]))
        self.assertEqual(ae.check_signatures_unchanged(old, new), [])

    def test_patch_signatures_may_change_freely(self):
        # Patches are recut against whatever history is on disk; theirs moving is
        # expected and must not block a release.
        old = feed(signed_item("0.3.60", "69", "SAME", deltas=[("68", "OLD")]))
        new = feed(signed_item("0.3.60", "69", "SAME", deltas=[("68", "NEW")]))
        self.assertEqual(ae.check_signatures_unchanged(old, new), [])

    def test_a_brand_new_item_has_nothing_to_compare(self):
        old = feed(signed_item("0.3.60", "69", "SAME"))
        new = feed(signed_item("0.3.61", "70", "FRESH"), signed_item("0.3.60", "69", "SAME"))
        self.assertEqual(ae.check_signatures_unchanged(old, new), [])

    def test_an_item_that_rolled_off_is_not_a_change(self):
        old = feed(signed_item("0.3.60", "69", "SAME"), signed_item("0.3.55", "64", "GONE"))
        new = feed(signed_item("0.3.60", "69", "SAME"))
        self.assertEqual(ae.check_signatures_unchanged(old, new), [])


if __name__ == "__main__":
    unittest.main()

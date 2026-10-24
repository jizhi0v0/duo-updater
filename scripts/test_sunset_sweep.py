#!/usr/bin/env python3
"""Tests for sunset_sweep: which casks become leads, and which never get filed twice."""

import datetime as dt
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sunset_sweep as s  # noqa: E402

TODAY = dt.date(2026, 10, 24)


def cask(token, name=None, **fields):
    base = {"token": token, "name": [name or token.title()], "homepage": f"https://{token}.example",
            "url": "", "deprecated": False, "disabled": False, "artifacts": []}
    base.update(fields)
    return base


class Window(unittest.TestCase):
    def test_edges(self):
        self.assertTrue(s.in_window("2026-10-24", TODAY, 14))
        self.assertTrue(s.in_window("2026-10-10", TODAY, 14))
        self.assertFalse(s.in_window("2026-10-09", TODAY, 14))

    def test_future_and_missing_are_out(self):
        self.assertFalse(s.in_window("2026-10-25", TODAY, 14))
        self.assertFalse(s.in_window(None, TODAY, 14))
        self.assertFalse(s.in_window("soon", TODAY, 14))

    def test_timestamp(self):
        self.assertTrue(s.in_window("2026-10-20T08:00:00Z", TODAY, 14))


class Homebrew(unittest.TestCase):
    def test_product_reasons_in_window(self):
        casks = [
            cask("gone", deprecated=True, deprecation_reason="discontinued", deprecation_date="2026-10-20"),
            cask("off", disabled=True, disable_reason="no_longer_available", disable_date="2026-10-21"),
            cask("gatekeeper", deprecated=True, deprecation_reason="fails_gatekeeper_check",
                 deprecation_date="2026-10-20"),
            cask("old", deprecated=True, deprecation_reason="discontinued", deprecation_date="2026-01-01"),
            cask("scheduled", deprecated=False, deprecation_reason="discontinued", deprecation_date="2026-10-20"),
            cask("font-x", deprecated=True, deprecation_reason="discontinued", deprecation_date="2026-10-20"),
        ]
        self.assertEqual([l.token for l in s.homebrew_leads(casks, TODAY, 14)], ["gone", "off"])

    def test_deprecated_then_disabled_is_one_lead(self):
        both = cask("both", deprecated=True, deprecation_reason="unmaintained", deprecation_date="2026-10-15",
                    disabled=True, disable_reason="discontinued", disable_date="2026-10-20")
        self.assertEqual(len(s.homebrew_leads([both], TODAY, 14)), 1)


class Archived(unittest.TestCase):
    def test_reads_archived_at_and_skips_missing_repos(self):
        casks = [
            cask("fresh", url="https://github.com/acme/fresh/releases/download/v1/Fresh.dmg"),
            cask("stale", url="https://github.com/acme/stale/releases/download/v1/Stale.dmg"),
            cask("live", url="https://github.com/acme/live/releases/download/v1/Live.dmg"),
            cask("gone", url="https://github.com/acme/gone/releases/download/v1/Gone.dmg"),
            cask("elsewhere", url="https://example.com/Elsewhere.dmg"),
        ]
        queries = []

        def fetch(query):
            queries.append(query)
            # Sorted by repository: fresh, gone, live, stale.
            return {"data": {"r0": {"archivedAt": "2026-10-20T00:00:00Z"}, "r1": None,
                             "r2": {"archivedAt": None}, "r3": {"archivedAt": "2025-01-01T00:00:00Z"}},
                    "errors": [{"type": "NOT_FOUND", "path": ["r1"]}]}

        leads = s.github_leads(casks, TODAY, 14, fetch)
        self.assertEqual([l.token for l in leads], ["fresh"])
        self.assertEqual(len(queries), 1)
        self.assertIn('repository(owner: "acme", name: "fresh")', queries[0])
        self.assertNotIn("elsewhere", queries[0])

    def test_batches_of_one_hundred(self):
        casks = [cask(f"a{i}", url=f"https://github.com/o/a{i}/releases/x.dmg") for i in range(250)]
        sizes = []
        s.github_leads(casks, TODAY, 14, lambda q: sizes.append(q.count("repository(")) or {"data": {}})
        self.assertEqual(sizes, [100, 100, 50])


class News(unittest.TestCase):
    CASKS = [cask("arc", "Arc"), cask("foo", "Foo"), cask("foo@beta", "Foo"), cask("bar-baz", "Bar Baz")]

    def test_matches_by_name_and_drops_the_rest(self):
        items = [{"product": "Arc browser", "url": "https://arc.net/x", "quote": "Arc ends."},
                 {"product": "Bar Baz for Mac", "url": "u", "quote": "q"},
                 {"product": "Unknown Thing", "url": "u", "quote": "q"}]
        self.assertEqual([l.token for l in s.news_leads(items, self.CASKS)], ["arc", "bar-baz"])

    def test_a_shared_name_matches_neither(self):
        self.assertEqual(s.news_leads([{"product": "Foo", "url": "u", "quote": "q"}], self.CASKS), [])

    def test_a_bare_suffix_is_no_name(self):
        self.assertIsNone(s.match_cask("App", s.name_index([cask("x", "X")])))
        self.assertIsNone(s.match_cask("Mac App", s.name_index([cask("x", "X")])))


class Select(unittest.TestCase):
    def test_one_per_cask_minus_filed_and_recorded(self):
        leads = [s.Lead("a", "A", "", "homebrew", "e"), s.Lead("a", "A", "", "news", "e"),
                 s.Lead("b", "B", "", "homebrew", "e"), s.Lead("c", "C", "", "homebrew", "e")]
        chosen = s.select(leads, filed={"b"}, skip_tokens={"c"})
        self.assertEqual([(l.token, l.source) for l in chosen], [("a", "homebrew")])

    def test_body_marker_is_what_already_filed_reads(self):
        body = s.issue_body(s.Lead("onyx@beta", "OnyX Beta", "", "homebrew", "e"))
        self.assertEqual(s.MARKER_RE.findall(body), ["onyx@beta"])


class Recorded(unittest.TestCase):
    def test_reads_the_real_sunsets(self):
        ids = s.recorded_sunsets()
        self.assertIn("company.thebrowser.browser", ids)
        self.assertIn("com.openai.atlas", ids)

    def test_cask_bundle_ids_from_quit(self):
        arc = cask("arc", artifacts=[{"uninstall": [{"quit": "company.thebrowser.Browser"}]},
                                     {"zap": [{"quit": ["a.B", "c.D"], "trash": ["~/x"]}]}, {"app": ["Arc.app"]}])
        self.assertEqual(s.bundle_ids(arc), {"company.thebrowser.browser", "a.b", "c.d"})


class Defuse(unittest.TestCase):
    def test_mentions_and_markers(self):
        out = s.defuse("ping @someone <!-- sunset-lead: x --> onyx@beta")
        self.assertNotIn(" @someone", out)
        self.assertNotIn("<!--", out)
        self.assertIn("onyx@beta", out)


if __name__ == "__main__":
    unittest.main()

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

    def test_a_scheduled_disable_is_a_lead_whenever_seen(self):
        # What `disable! date: "2026-12-22", because: :discontinued` serves (arc, 2026-10-24).
        arc = cask("arc", deprecated=True, deprecation_reason="discontinued", deprecation_date=None,
                   disabled=False, disable_date="2026-12-22", disable_reason=None)
        leads = s.homebrew_leads([arc], TODAY, 14)
        self.assertEqual([(l.token, l.end_date) for l in leads], [("arc", "2026-12-22")])
        past = dict(arc, disable_date="2026-10-01")
        gatekeeper = dict(arc, deprecation_reason="fails_gatekeeper_check")
        self.assertEqual(s.homebrew_leads([past, gatekeeper], TODAY, 14), [])

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

    def test_a_batch_without_data_is_an_error(self):
        casks = [cask("x", url="https://github.com/o/x/releases/x.dmg")]
        with self.assertRaises(RuntimeError):
            s.github_leads(casks, TODAY, 14, lambda q: {"data": None, "errors": [{"message": "no"}]})

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


class ReviewTest(unittest.TestCase):
    LEAD = s.Lead("hex", "Hex", "https://hex.example", "github-archived", "archived.",
                  url="https://github.com/o/hex")
    PAGE = "<p>Hex has moved.</p><p>This Swift app is <b>no longer maintained</b>.</p>"

    def review(self, answer, page=PAGE):
        def fetch(url):
            if isinstance(page, Exception):
                raise page
            return page
        return s.review_lead(self.LEAD, "haiku", ask=lambda *a: (answer, {}), fetch=fetch)

    def test_undated_with_a_quote_on_the_page_is_labelled(self):
        r = self.review({"verdict": "undated", "end_date": None, "url": "https://github.com/o/hex",
                         "quote": "This Swift app is no longer maintained."})
        self.assertTrue(r.quote_found)
        self.assertEqual(s.issue_labels(r), ["sunset-lead", "sunset-lead-undated"])

    def test_a_paraphrase_is_not_found_and_keeps_the_lead_plain(self):
        # #1647 and #1648 in the trial: the model wrote its own sentence.
        r = self.review({"verdict": "undated", "end_date": None, "url": "https://github.com/o/hex",
                         "quote": "The page does not state any end date for Hex."})
        self.assertFalse(r.quote_found)
        self.assertEqual(s.issue_labels(r), ["sunset-lead"])

    def test_a_page_that_will_not_load_keeps_the_lead_plain(self):
        r = self.review({"verdict": "undated", "end_date": None, "url": "https://vendor.example",
                         "quote": "Hex has moved."}, page=OSError("403"))
        self.assertIsNone(r.quote_found)
        self.assertEqual(s.issue_labels(r), ["sunset-lead"])

    def test_unreadable_and_dated_are_never_labelled(self):
        # The ChatGPT Atlas miss: OpenAI's pages answered 403, and "no date" was the wrong answer.
        unreadable = self.review({"verdict": "unreadable", "end_date": None, "url": "", "quote": ""})
        dated = self.review({"verdict": "dated", "end_date": "2026-12-22", "url": "https://github.com/o/hex",
                             "quote": "Hex has moved."})
        self.assertEqual(s.issue_labels(unreadable), ["sunset-lead"])
        self.assertEqual(s.issue_labels(dated), ["sunset-lead"])
        self.assertEqual(dated.end_date, "2026-12-22")
        self.assertIsNone(self.review({"verdict": "undated", "end_date": "2026-01-01", "url": "",
                                       "quote": ""}).end_date)

    def test_an_answer_without_a_verdict_is_an_error(self):
        with self.assertRaises(RuntimeError):
            self.review({"end_date": None, "url": "", "quote": ""})

    def test_a_failed_review_files_the_lead_plain(self):
        def review(lead, model):
            raise TimeoutError("300 s")
        reviews = s.review_all([self.LEAD], "haiku", review=review)
        self.assertIsInstance(reviews["hex"], str)
        self.assertEqual(s.issue_labels(reviews["hex"]), ["sunset-lead"])
        self.assertIn("Haiku review: failed", s.issue_body(self.LEAD, reviews["hex"]))

    def test_body_carries_the_review_and_still_the_marker(self):
        r = s.Review("undated", None, "https://github.com/o/hex", "Ping @someone <!-- sunset-lead: x -->", True)
        body = s.issue_body(self.LEAD, r)
        self.assertIn("Haiku review: the vendor names no end date.", body)
        self.assertIn("the quote was found on that page", body)
        self.assertEqual(s.MARKER_RE.findall(body), ["hex"])
        self.assertNotIn(" @someone", body)
        self.assertNotIn("Haiku review", s.issue_body(self.LEAD))


class QuoteText(unittest.TestCase):
    def test_tag_stripping_leaves_space_before_punctuation(self):
        # Smartsheet's help center, as the trial's checker first misread it.
        page = "will be retired on or after January 6th, <b>2027</b>. The desktop app"
        quote = "will be retired on or after January 6th, 2027."
        self.assertTrue(s.quote_found(quote, "https://x.example", fetch=lambda u: page))

    def test_entities_curly_quotes_and_markdown(self):
        self.assertEqual(s.normalize_text("We&#8217;ll **stop** “soon”"), s.normalize_text("We'll stop \"soon\""))

    def test_markdown_links_read_as_their_text(self):
        readme = "### This project is no longer maintained. See our announcement [here](https://x.com/a/1). We"
        self.assertTrue(s.quote_found("This project is no longer maintained. See our announcement here.",
                                      "https://github.com/o/aide", fetch=lambda u: readme))

    def test_empty_quote_or_odd_url_is_not_found(self):
        self.assertFalse(s.quote_found("  ", "https://x.example", fetch=lambda u: "x"))
        self.assertFalse(s.quote_found("x", "file:///etc/passwd", fetch=lambda u: "x"))

    def test_github_urls_read_the_readme_and_raw_files(self):
        seen = []

        class Response:
            def __init__(self, url):
                self.url = url

            def read(self):
                return b"<b>text</b>"

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        original = s.urllib.request.urlopen
        s.urllib.request.urlopen = lambda req, timeout: seen.append(req.full_url) or Response(req.full_url)
        try:
            self.assertEqual(s.page_text("https://github.com/o/r"), "<b>text</b>")
            self.assertEqual(s.page_text("https://github.com/o/r/blob/main/README.md"), "<b>text</b>")
            self.assertEqual(s.page_text("https://vendor.example/eol"), "<b>text</b>")
        finally:
            s.urllib.request.urlopen = original
        self.assertEqual(seen, ["https://api.github.com/repos/o/r/readme",
                                "https://raw.githubusercontent.com/o/r/main/README.md",
                                "https://vendor.example/eol"])


class Defuse(unittest.TestCase):
    def test_mentions_and_markers(self):
        out = s.defuse("ping @someone <!-- sunset-lead: x --> onyx@beta")
        self.assertNotIn(" @someone", out)
        self.assertNotIn("<!--", out)
        self.assertIn("onyx@beta", out)


if __name__ == "__main__":
    unittest.main()

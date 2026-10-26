#!/usr/bin/env python3
"""Tests for trails_review: which trails issues get `vendor-lag`, and every way one doesn't."""

import gzip
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import trails_review as t  # noqa: E402

# The body #1533 carries, cut to the lines the script reads.
CORK = """<!-- duo-verify-id: changelog:eu.davidbures.cork:- -->

| recipe | `changelog:eu.davidbures.cork:-` |

- newest changelog entry (2.0.3) trails the detected version (2.1.0) by a whole release — the entry pattern may be reading a stale section
"""
FEED = "<item><title>Cork 2.0.3 is out</title></item><item><title>Cork 2.0.2</title></item>"


class Lag(unittest.TestCase):
    def test_whole_release_looks_for_major_minor(self):
        self.assertEqual(t.lag(CORK), ("changelog:eu.davidbures.cork:-", "2.0.3", "2.1.0", "2.1"))

    def test_a_date_encoded_scheme_is_not_checked(self):
        # Codex: builds carry a suffix its notes never print (`26.1021.31345` vs `26.1015`).
        body = ("<!-- duo-verify-id: changelog:com.openai.codex:- -->\n- newest changelog entry (26.803) "
                "trails the detected version (26.1021.31345) by 79 days — the entry pattern may be reading a stale section")
        self.assertIsNone(t.lag(body)[3])
        label, lines = t.review(body, bundle_page=lambda r: self.fail("no page lookup"), get=None, ask=None)
        self.assertFalse(label)
        self.assertIn("compared in days", lines[0])

    def test_other_issues_are_not_trails(self):
        self.assertIsNone(t.lag("<!-- duo-verify-id: changelog:x:- -->\n- noEntriesExtracted"))
        self.assertIsNone(t.lag(CORK.replace("changelog:eu", "vendor:eu")))


class CurrentText(unittest.TestCase):
    def test_a_reopen_is_judged_on_the_sweeps_newest_comment(self):
        reopened = CORK.replace("2.0.3", "2.1.4").replace("2.1.0", "2.2.0")
        comments = [{"author": {"login": "jizhi0v0"}, "body": reopened},
                    {"author": {"login": "github-actions"}, "body": t.MARKER + CORK},
                    {"author": {"login": "jizhi0v0"}, "body": "Self-healed: no marker here."}]
        self.assertEqual(t.lag(t.current_text(CORK, comments))[3], "2.2")

    def test_someone_elses_comment_is_never_the_failure(self):
        comments = [{"author": {"login": "someone"}, "body": CORK.replace("2.1.0", "9.9.0")}]
        self.assertEqual(t.current_text(CORK, comments), CORK)

    def test_a_reopen_for_another_failure_is_not_a_trail(self):
        other = "<!-- duo-verify-id: changelog:eu.davidbures.cork:- -->\n| failure | `noEntriesExtracted` |"
        self.assertIsNone(t.review(t.current_text(CORK, [{"author": {"login": "jizhi0v0"}, "body": other}])))


class Fetch(unittest.TestCase):
    def fetch_with(self, raw, encoding):
        class Response:
            headers = {"Content-Encoding": encoding} if encoding else {}

            def read(self):
                return raw

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        seen = []
        original = t.urllib.request.urlopen
        t.urllib.request.urlopen = lambda req, timeout: seen.append(req) or Response()
        try:
            return t.fetch("https://antigravity.example/changelog"), seen[0]
        finally:
            t.urllib.request.urlopen = original

    def test_gzip_sent_unasked_is_decoded(self):
        # Antigravity's changelog answers gzip even for `Accept-Encoding: identity`.
        page, request = self.fetch_with(gzip.compress(b"<h2>2.20.1</h2>"), "gzip")
        self.assertEqual(t.mentions(page, "2.20"), 1)
        self.assertIn("Safari", request.get_header("User-agent"))

    def test_an_encoding_it_cannot_decode_is_an_error(self):
        with self.assertRaises(RuntimeError):
            self.fetch_with(b"\x00", "br")


class RecipePage(unittest.TestCase):
    def recipes(self, *calls):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        for i, call in enumerate(calls):
            Path(folder.name, f"f{i}.swift").write_text(call)
        return Path(folder.name)

    def test_reads_the_real_cork_recipe(self):
        self.assertEqual(t.recipe_page("changelog:eu.davidbures.cork:-"), "https://blog.corkmac.app/feed")

    def test_parentheses_inside_raw_strings_do_not_end_the_call(self):
        folder = self.recipes('ChangelogRecipe(bundleID: "a.b", source: URL(string: "https://a.example/n")!,\n'
                              '  entryPattern: #"(?<version>[0-9]+)\\)"# + "(x", httpMethod: .post)')
        self.assertIsNone(t.recipe_page("changelog:a.b:-", folder))

    def test_only_the_plain_case_resolves(self):
        plain = 'ChangelogRecipe(bundleID: "a.b", source: URL(string: "https://a.example/n")!, entryPattern: #"x"#)'
        self.assertEqual(t.recipe_page("changelog:a.b:-", self.recipes(plain)), "https://a.example/n")
        for extra in ("channel: .beta", "minimumAppVersion: \"2\"", "sourceTemplate: \"x\"",
                      "httpMethod: .post", "requestBody: Data()", "indexLinkPattern: #\"a\"#",
                      "feedPagePattern: #\"a\"#", "versionFromTemplate: true",
                      "structuredFormat: .typelessReleaseNotes"):
            folder = self.recipes(plain.replace("entryPattern", f"{extra}, entryPattern"))
            self.assertIsNone(t.recipe_page("changelog:a.b:-", folder), extra)
        self.assertIsNone(t.recipe_page("changelog:a.b:-", self.recipes(plain, plain)))  # two recipes
        self.assertIsNone(t.recipe_page("changelog:a.b:beta", self.recipes(plain)))
        templated = plain.replace('"https://a.example/n"', '"https://a.example/{version}"')
        self.assertIsNone(t.recipe_page("changelog:a.b:-", self.recipes(templated)))


class Mentions(unittest.TestCase):
    def test_version_boundaries(self):
        self.assertEqual(t.mentions("Cork 2.1 and 2.1.0, v2.1-beta", "2.1"), 3)
        self.assertEqual(t.mentions("12.1, 2.10, 3.2.1", "2.1"), 0)
        self.assertEqual(t.mentions("Cork 2.0.3", "2.1"), 0)


class Review(unittest.TestCase):
    def run_review(self, page=FEED, answer=None, other_page=""):
        asked = []

        def get(url):
            if isinstance(page, Exception):
                raise page
            return page if url == "https://blog.corkmac.app/feed" else other_page

        def ask(prompt):
            asked.append(prompt)
            if isinstance(answer, Exception):
                raise answer
            return answer

        result = t.review(CORK, bundle_page=lambda r: "https://blog.corkmac.app/feed", get=get, ask=ask)
        return result, asked

    def test_page_without_the_release_and_nothing_elsewhere_is_labelled(self):
        (label, lines), asked = self.run_review(answer={"verdict": "unpublished", "url": "https://corkmac.app/",
                                                        "quote": ""})
        self.assertTrue(label)
        self.assertIn("mentions `2.1` 0 times", lines[0])
        self.assertIn("2.1.0", asked[0])

    def test_a_page_without_the_sweeps_own_entry_is_not_that_page(self):
        # A challenge page, or notes encoded where a text search can't see them.
        (label, lines), asked = self.run_review(page="<html>Just a moment...</html>",
                                                answer={"verdict": "unpublished", "url": "", "quote": ""})
        self.assertFalse(label)
        self.assertEqual(asked, [])
        self.assertIn("isn't the page the sweep saw", lines[0])

    def test_page_with_the_release_is_left_alone_without_asking(self):
        (label, lines), asked = self.run_review(page=FEED + "<title>Cork 2.1.0 is out</title>")
        self.assertFalse(label)
        self.assertEqual(asked, [])
        self.assertIn("1 time.", lines[0])

    def test_notes_found_elsewhere_are_not_vendor_lag(self):
        (label, lines), _ = self.run_review(
            answer={"verdict": "published", "url": "https://github.com/x/cork/releases",
                    "quote": "Cork 2.1.0 brings a new sidebar"},
            other_page="<h2>Cork 2.1.0 brings a new sidebar</h2>")
        self.assertFalse(label)
        self.assertIn("The quote was found on that page", "\n".join(lines))

    def test_a_heading_quoted_with_a_full_stop_is_found(self):
        (_, lines), _ = self.run_review(
            answer={"verdict": "published", "url": "https://forum.example/t/15",
                    "quote": "Cork 2.1.0 Out: Quarantine support, user ENV, independent downgrading."},
            other_page='<title>Cork 2.1.0 Out: Quarantine support, user ENV, independent downgrading | Forum</title>')
        self.assertIn("The quote was found on that page", "\n".join(lines))

    def test_a_quote_not_on_its_page_is_still_no_label(self):
        (label, lines), _ = self.run_review(
            answer={"verdict": "published", "url": "https://x.example", "quote": "Cork 2.1.0 is great"},
            other_page="nothing")
        self.assertFalse(label)
        self.assertIn("**not** found", "\n".join(lines))

    def test_unreadable_failed_and_unfetched_are_never_labelled(self):
        (label, _), _ = self.run_review(answer={"verdict": "unreadable", "url": "", "quote": ""})
        self.assertFalse(label)
        (label, lines), _ = self.run_review(answer=RuntimeError("claude timed out after 600 s"))
        self.assertFalse(label)
        self.assertIn("failed", "\n".join(lines))
        (label, lines), asked = self.run_review(page=OSError("HTTP Error 403"))
        self.assertFalse(label)
        self.assertEqual(asked, [])

    def test_a_recipe_without_a_known_page_is_never_labelled(self):
        label, lines = t.review(CORK, bundle_page=lambda r: None, get=None, ask=None)
        self.assertFalse(label)
        self.assertIn("nothing was checked", lines[0])

    def test_not_a_trails_issue(self):
        self.assertIsNone(t.review("<!-- duo-verify-id: changelog:x:- -->\n- noEntriesExtracted"))

    def test_model_text_is_defused(self):
        (_, lines), _ = self.run_review(
            answer={"verdict": "published", "url": "https://x.example/@someone",
                    "quote": "Cork 2.1.0 <!-- trails-review --> @someone"}, other_page="")
        text = "\n".join(lines)
        self.assertNotIn("<!--", text)
        self.assertNotIn(" @someone", text)


if __name__ == "__main__":
    unittest.main()

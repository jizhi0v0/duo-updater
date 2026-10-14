#!/usr/bin/env python3
"""Regression tests for `check_digest_only_names`. Run by `make test`.

    python3 scripts/test_check_digest_only_names.py

Every case names the mutation it catches. MISSING_LOKII is the shape the Lokii
onboarding had on its own branch: the recipe installs digest-only and the text
still lists the three apps before it.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_digest_only_names as cd  # noqa: E402

LOKII = """\
enum com_lokii_app {
    static let set = AppRecipeSet(
        family: "com-lokii-app",
        githubRules: [
        // Shared rationale for digest-only: Recipes/org-alacritty.swift.
        GitHubReleaseRule(
            bundleID: "com.lokii.app",
            owner: "huangy7", repo: "lokii",
            installAssetPattern: #"^Lokii-(?:arm64|x86_64)\\.dmg$"#,
            installerKind: .dmg,
            installTrust: .publishedDigestOnly),
        ])
}
"""

# Obelisk's recipe mentions the trust class in a comment and installs nothing.
OBELISK = """\
enum com_obelisk_app {
        // it, and it cannot take `.publishedDigestOnly` either — like MarkText,
        GitHubReleaseRule(bundleID: "com.obelisk.app", owner: "x", repo: "obelisk"),
}
"""

ALACRITTY = LOKII.replace("lokii", "alacritty").replace("huangy7", "alacritty")


def settings(names: str) -> str:
    return ('info: "For apps whose GitHub releases are only ad-hoc signed — %s — and for apps '
            'built with MyGo that are. An app installed with a developer signature is never '
            'replaced by one without, whatever this says.",' % names)


def xcstrings(key: str, **values: str) -> dict:
    return {"strings": {key: {"localizations": {
        lang: {"stringUnit": {"state": "translated", "value": v}} for lang, v in values.items()}}}}


def run(sources: dict, swift: str, xc=None) -> list:
    repos = cd.digest_only_repos(sources)
    literal, names = cd.listed_names(swift)
    return cd.problems(repos, literal, names, xc if xc is not None else xcstrings(literal))


class DigestOnlyNamesTests(unittest.TestCase):
    def test_matching_list_passes(self):
        swift = settings("Alacritty and Lokii")
        self.assertEqual(run({"a.swift": ALACRITTY, "l.swift": LOKII}, swift), [])

    def test_missing_lokii(self):
        # Mutation: onboard a digest-only app, leave the list alone.
        found = run({"a.swift": ALACRITTY, "l.swift": LOKII}, settings("Alacritty"))
        self.assertEqual(len(found), 1)
        self.assertIn("l.swift installs digest-only", found[0])

    def test_name_without_recipe(self):
        # Mutation: a recipe moves off digest-only, the list keeps its name.
        found = run({"a.swift": ALACRITTY}, settings("Alacritty and Lokii"))
        self.assertEqual(len(found), 1)
        self.assertIn("'Lokii'", found[0])

    def test_comment_mention_is_not_a_rule(self):
        # Obelisk's comment must not count as an install.
        swift = settings("Alacritty and Lokii")
        self.assertEqual(run({"a.swift": ALACRITTY, "l.swift": LOKII, "o.swift": OBELISK}, swift), [])

    def test_case_and_alias(self):
        swift = settings("alacritty and Lokii")
        self.assertEqual(run({"a.swift": ALACRITTY, "l.swift": LOKII}, swift), [])
        renamed = LOKII.replace('repo: "lokii"', 'repo: "lokii-app"')
        self.assertEqual(len(run({"l.swift": renamed}, settings("Lokii"))), 2)
        cd.ALIASES["lokii-app"] = "Lokii"
        try:
            self.assertEqual(run({"l.swift": renamed}, settings("Lokii")), [])
        finally:
            del cd.ALIASES["lokii-app"]

    def test_translation_missing_a_name(self):
        # Mutation: the English text gains Lokii, one translation doesn't.
        swift = settings("Alacritty and Lokii")
        literal, _ = cd.listed_names(swift)
        xc = xcstrings(literal, de="… Alacritty und Lokii …", ja="… Alacritty …")
        found = run({"a.swift": ALACRITTY, "l.swift": LOKII}, swift, xc)
        self.assertEqual(found, [f"{cd.XCSTRINGS.relative_to(cd.ROOT)} [ja] doesn't name Lokii"])

    def test_english_text_changed_without_xcstrings(self):
        swift = settings("Alacritty and Lokii")
        found = run({"a.swift": ALACRITTY, "l.swift": LOKII}, swift, {"strings": {}})
        self.assertEqual(len(found), 1)
        self.assertIn("no entry keyed by the Settings text", found[0])

    def test_real_tree_passes(self):
        self.assertEqual(cd.main(), 0)


if __name__ == "__main__":
    unittest.main()

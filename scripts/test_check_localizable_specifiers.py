#!/usr/bin/env python3
"""Regression tests for `check_localizable_specifiers`. Run by `make test`.

    python3 scripts/test_check_localizable_specifiers.py

The must-hit fixtures are the real shape that crashed DuoUpdater on 2026-09-19,
not an invented one: a plural whose singular spells the number out, loses its
`%lld`, and lets the following `%@` read the count as an object pointer.

The must-not-hit fixtures matter just as much here. A first draft of this
checker read the trailing `@` of `%#@releases@` as an object specifier and
reported fourteen failures against a catalog that was correct — a gate that
cries wolf on its first run is a gate nobody keeps.
"""

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_localizable_specifiers as cls  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parent.parent
REAL_CATALOG = REPO / "App" / "Resources" / "Localizable.xcstrings"

# The key and the singular that shipped. `one` carries no `%lld`, so `%@` is the
# first specifier and reads argument one — the Int.
CRASHING_KEY = "There are %lld backups on this Mac, %@. New backups will be kept on the disk either way."
CRASHING_ONE = "There is 1 backup on this Mac, %@. New backups will be kept on the disk either way."
FIXED_ONE = "There is 1 backup on this Mac, %2$@. New backups will be kept on the disk either way."
GOOD_OTHER = "There are %1$lld backups on this Mac, %2$@. New backups will be kept on the disk either way."


def plural(one: str, other: str) -> dict:
    return {
        "variations": {
            "plural": {
                "one": {"stringUnit": {"state": "translated", "value": one}},
                "other": {"stringUnit": {"state": "translated", "value": other}},
            }
        }
    }


def flat(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog(strings: dict) -> dict:
    return {"sourceLanguage": "en", "version": "1.0", "strings": strings}


def padding(count: int) -> dict:
    """Keys that are fine, to clear the checker's "did this really run" floor."""
    return {
        f"Padding %lld item {i}": {"localizations": {"en": flat(f"Padding %lld item {i}")}}
        for i in range(count)
    }


class SpecifierCheck(unittest.TestCase):
    def run_on(self, strings: dict) -> tuple[list[str], int]:
        merged = dict(padding(60))
        merged.update(strings)
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "Localizable.xcstrings"
            path.write_text(json.dumps(catalog(merged), ensure_ascii=False))
            failures, keys, _ = cls.check(path)
        return failures, keys

    # MARK: must hit

    def test_the_singular_that_crashed_is_caught(self):
        """Mutation: restore the shipped `one` variant. Must fail."""
        failures, _ = self.run_on(
            {CRASHING_KEY: {"localizations": {"en": plural(CRASHING_ONE, GOOD_OTHER)}}})
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("argument 1 as object", failures[0])
        self.assertIn("integer", failures[0])

    def test_a_swapped_pair_is_caught(self):
        """Both specifiers present, in the wrong order. Formats garbage.

        One line per variant, not per specifier: the first wrong slot is enough
        to say the sentence is wrong, and listing every knock-on mismatch would
        bury the one that matters.
        """
        failures, _ = self.run_on(
            {"Moved %lld files to %@": {
                "localizations": {"de": flat("Nach %@ wurden %lld Dateien verschoben")}}})
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("argument 1 as object", failures[0])

    def test_an_argument_the_key_does_not_pass_is_caught(self):
        failures, _ = self.run_on(
            {"Moved %lld files to %@": {
                "localizations": {"fr": flat("%1$lld / %2$@ / %3$@")}}})
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("argument 3", failures[0])

    def test_mixing_positional_and_implicit_is_caught(self):
        failures, _ = self.run_on(
            {"Moved %lld files to %@": {
                "localizations": {"es": flat("%1$lld archivos a %@")}}})
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("mixes", failures[0])

    def test_a_substitution_pointed_at_the_wrong_argument_is_caught(self):
        failures, _ = self.run_on(
            {"%lld releases across %@": {
                "localizations": {"en": {
                    "stringUnit": {"state": "translated", "value": "%#@releases@ across %2$@"},
                    "substitutions": {
                        "releases": {
                            "argNum": 2, "formatSpecifier": "lld",
                            "variations": {"plural": {
                                "one": {"stringUnit": {"value": "%lld release"}},
                                "other": {"stringUnit": {"value": "%lld releases"}}}}}}}}}})
        self.assertTrue(any("argument 2 as integer" in f for f in failures), failures)

    def test_a_substitution_body_with_the_wrong_type_is_caught(self):
        failures, _ = self.run_on(
            {"%lld releases": {
                "localizations": {"en": {
                    "stringUnit": {"state": "translated", "value": "%#@releases@"},
                    "substitutions": {
                        "releases": {
                            "argNum": 1, "formatSpecifier": "lld",
                            "variations": {"plural": {
                                "one": {"stringUnit": {"value": "%@ release"}},
                                "other": {"stringUnit": {"value": "%lld releases"}}}}}}}}}})
        self.assertTrue(any("declares integer" in f for f in failures), failures)

    # MARK: must not hit

    def test_the_fix_passes(self):
        failures, _ = self.run_on(
            {CRASHING_KEY: {"localizations": {"en": plural(FIXED_ONE, GOOD_OTHER)}}})
        self.assertEqual(failures, [])

    def test_a_named_substitution_is_not_a_failure(self):
        """The shape Xcode writes for plurals, and the one a first draft of this
        checker reported fourteen times against a correct catalog."""
        failures, _ = self.run_on(
            {"%lld releases across %lld apps": {
                "localizations": {"zh-Hans": {
                    "stringUnit": {"state": "translated", "value": "%#@releases@，涉及 %#@apps@"},
                    "substitutions": {
                        "releases": {
                            "argNum": 1, "formatSpecifier": "lld",
                            "variations": {"plural": {
                                "other": {"stringUnit": {"value": "%lld 个版本"}}}}},
                        "apps": {
                            "argNum": 2, "formatSpecifier": "lld",
                            "variations": {"plural": {
                                "other": {"stringUnit": {"value": "%lld 个应用"}}}}}}}}}})
        self.assertEqual(failures, [])

    def test_reordering_with_positions_is_allowed(self):
        failures, _ = self.run_on(
            {"Moved %lld files to %@": {
                "localizations": {"ja": flat("%2$@ に %1$lld 件を移動しました")}}})
        self.assertEqual(failures, [])

    def test_a_literal_percent_carries_no_argument(self):
        failures, _ = self.run_on(
            {"%lld%% of %@": {"localizations": {"en": flat("%lld%% of %@")}}})
        self.assertEqual(failures, [])

    def test_keys_without_specifiers_are_not_examined(self):
        _, keys = self.run_on({"Delete backups": {"localizations": {"en": flat("Backups löschen")}}})
        self.assertEqual(keys, 60)

    # MARK: the run itself

    def test_a_catalog_too_small_to_be_real_fails(self):
        """Vacuity guard: a parse that silently stops matching must not pass."""
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "Localizable.xcstrings"
            path.write_text(json.dumps(catalog({"One %@": {"localizations": {"en": flat("One %@")}}})))
            failures, keys, _ = cls.check(path)
            self.assertEqual(failures, [])
            self.assertLess(keys, 50)

    def test_the_real_catalog_passes(self):
        failures, keys, variants = cls.check(REAL_CATALOG)
        self.assertEqual(failures, [], failures[:5])
        self.assertGreater(keys, 100)
        self.assertGreater(variants, 500)


if __name__ == "__main__":
    unittest.main(verbosity=2)

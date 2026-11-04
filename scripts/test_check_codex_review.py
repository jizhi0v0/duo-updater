#!/usr/bin/env python3
"""The review gate must never accept a spoofed, stale or incomplete review."""
import json
import unittest
from unittest.mock import patch

import check_codex_review as gate

HEAD = "a" * 40


def receipt(head=HEAD, status="completed", findings=False, unresolved=False, **extra):
    review = {"commit_sha": head, "status": status, "has_any_findings": findings,
              "has_unresolved_findings": unresolved, **extra}
    return {"id": 1, "user": {"login": gate.BOT},
            "body": gate.HEADER + "\n<!-- codex-review-state:v1 "
                    + json.dumps({"code_review": review}) + " -->"}


class ReviewGate(unittest.TestCase):
    def test_only_an_explicit_clean_current_receipt_passes(self):
        self.assertEqual(gate.verdict([receipt()], HEAD)[0], "success")
        for comment in [receipt(head="b" * 40), receipt(status="running"),
                        receipt(findings=None), receipt(unresolved=None),
                        {**receipt(), "user": {"login": "jizhi0v0"}}]:
            self.assertEqual(gate.verdict([comment], HEAD)[0], "pending")

    def test_findings_hold_the_merge_even_if_the_thread_was_resolved(self):
        self.assertEqual(gate.verdict([receipt(findings=True)], HEAD)[0], "failure")
        self.assertEqual(gate.verdict([receipt(unresolved=True)], HEAD)[0], "failure")

    def test_a_new_review_cannot_fall_back_to_an_earlier_clean_one(self):
        newer = {**receipt(status="running"), "id": 2}
        self.assertEqual(gate.verdict([receipt(), newer], HEAD)[0], "pending")
        self.assertEqual(gate.verdict([newer, receipt()], HEAD)[0], "pending")

    def test_bad_or_quoted_metadata_is_not_approval(self):
        for body in [gate.HEADER + "\n<!-- codex-review-state:v1 {} -->",
                     gate.HEADER + "\n<!-- codex-review-state:v1 INVALID -->",
                     "quoted: " + receipt()["body"]]:
            self.assertEqual(gate.verdict([{**receipt(), "body": body}], HEAD)[0], "pending")

    def test_a_push_between_receipt_and_final_read_cannot_pass(self):
        old = {"state": "open", "draft": False, "head": {"sha": HEAD}}
        moved = {**old, "head": {"sha": "b" * 40}}
        with patch("sys.argv", ["check", "--repo", "o/r", "--pr", "1", "--head", HEAD]), \
                patch.object(gate, "api", side_effect=[old, [receipt()], moved]):
            self.assertEqual(gate.main(), 1)

    def test_a_missing_receipt_times_out_instead_of_passing(self):
        pr = {"state": "open", "draft": False, "head": {"sha": HEAD}}
        with patch("sys.argv", ["check", "--repo", "o/r", "--pr", "1", "--head", HEAD,
                                "--timeout", "0"]), \
                patch.object(gate, "api", side_effect=[pr, []]):
            self.assertEqual(gate.main(), 1)

    def test_a_real_machine_hold_cannot_pass_a_clean_review(self):
        pr = {"state": "open", "draft": False, "head": {"sha": HEAD},
              "labels": [{"name": "needs-real-machine"}]}
        with patch("sys.argv", ["check", "--repo", "o/r", "--pr", "1", "--head", HEAD]), \
                patch.object(gate, "api", return_value=pr) as api:
            self.assertEqual(gate.main(), 1)
            self.assertEqual(api.call_count, 1)


if __name__ == "__main__":
    unittest.main()

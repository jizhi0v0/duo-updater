#!/usr/bin/env python3
"""The review gate must never accept a spoofed, stale or incomplete review."""
import json
import subprocess
import unittest
from unittest.mock import patch

import check_codex_review as gate

HEAD = "a" * 40
BASE = "b" * 40


def nightly_pr(kind="baseline"):
    return {"state": "open", "draft": False, "user": {"login": "o"},
            "head": {"sha": HEAD, "ref": f"verify/{kind}-20261105T010000Z",
                     "repo": {"full_name": "o/r"}},
            "base": {"sha": BASE}, "changed_files": 1}


def changed(path, **extra):
    return {"filename": path, "status": "modified", **extra}


def receipt(head=HEAD, status="completed", findings=False, unresolved=False, **extra):
    review = {"commit_sha": head, "status": status, "has_any_findings": findings,
              "has_unresolved_findings": unresolved, **extra}
    return {"id": 1, "user": {"login": gate.BOT},
            "body": gate.HEADER + "\n<!-- codex-review-state:v1 "
                    + json.dumps({"code_review": review}) + " -->"}


class ReviewGate(unittest.TestCase):
    def test_only_the_owners_timestamped_same_repo_scan_branches_qualify(self):
        pr = nightly_pr()
        self.assertTrue(gate.is_nightly_state(pr, "o/r", [changed("verify/baseline.json")]))
        for candidate in [
            {**pr, "user": {"login": "someone-else"}},
            {**pr, "head": {**pr["head"], "repo": {"full_name": "fork/r"}}},
            {**pr, "head": {**pr["head"], "repo": None}},
            {**pr, "head": {**pr["head"], "ref": "verify/baseline-custom"}},
            {**pr, "head": {**pr["head"], "ref": "feature/change"}},
        ]:
            self.assertFalse(gate.is_nightly_state(candidate, "o/r", [changed("verify/baseline.json")]))

    def test_install_scan_may_change_one_or_both_state_files(self):
        pr = nightly_pr("install")
        files = [changed("verify/identities.json"), changed("verify/install-baseline.json")]
        for subset in [files[:1], files[1:], files]:
            self.assertTrue(gate.is_nightly_state({**pr, "changed_files": len(subset)}, "o/r", subset))

    def test_extra_deleted_renamed_or_incomplete_files_prevent_the_exception(self):
        pr = nightly_pr()
        for files, count in [
            ([], 0),
            ([changed("verify/baseline.json"), changed("CLI/Sources/Example.swift")], 2),
            ([changed("verify/identities.json")], 1),
            ([changed("verify/baseline.json", status="removed")], 1),
            ([changed("verify/baseline.json", status="renamed", previous_filename="code.swift")], 1),
            ([changed("verify/baseline.json")], 2),
            ([changed("verify/baseline.json")], True),
        ]:
            self.assertFalse(gate.is_nightly_state({**pr, "changed_files": count}, "o/r", files))

    def test_scan_exception_uses_a_pinned_diff_without_requesting_a_review_receipt(self):
        pr = nightly_pr()
        with patch("sys.argv", self.publish_args()), \
                patch.object(gate, "api", side_effect=[pr, {"files": [changed("verify/baseline.json")]}, pr]) as api, \
                patch.object(gate, "write_api", return_value={}) as write:
            self.assertEqual(gate.main(), 0)
        self.assertEqual(api.call_args_list[1].args[0], f"repos/o/r/compare/{BASE}...{HEAD}")
        self.assertEqual(api.call_count, 3)
        self.assertEqual(write.call_args_list[-1].args[1]["description"],
                         "Nightly scan state only; review not required")

    def test_scan_exception_is_invalidated_by_a_push_or_changed_pr_metadata(self):
        pr = nightly_pr()
        for current in [
            {**pr, "head": {**pr["head"], "sha": "c" * 40}},
            {**pr, "base": {"sha": "c" * 40}},
            {**pr, "changed_files": 2},
            {**pr, "user": {"login": "someone-else"}},
            {**pr, "draft": True},
            {**pr, "labels": [{"name": "needs-real-machine"}]},
        ]:
            with patch("sys.argv", self.publish_args()), \
                    patch.object(gate, "api", side_effect=[pr, {"files": [changed("verify/baseline.json")]}, current]), \
                    patch.object(gate, "write_api", return_value={}) as write:
                self.assertEqual(gate.main(), 1)
            self.assertEqual(write.call_args_list[-1].args[1]["state"], "failure")

    def test_scan_branch_with_code_still_requires_a_clean_review(self):
        pr = {**nightly_pr(), "changed_files": 2}
        files = [changed("verify/baseline.json"), changed("CLI/Sources/Example.swift")]
        with patch("sys.argv", self.publish_args() + ["--timeout", "0"]), \
                patch.object(gate, "api", side_effect=[pr, {"files": files}, []]) as api, \
                patch.object(gate, "write_api", return_value={}) as write:
            self.assertEqual(gate.main(), 1)
        self.assertIn("issues/1/comments", api.call_args_list[-1].args[0])
        self.assertEqual(write.call_args_list[-1].args[1]["state"], "failure")

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

    def publish_args(self):
        return ["check", "--repo", "o/r", "--pr", "1", "--head", HEAD,
                "--publish-check", "--run-url", "https://github.com/o/r/actions/runs/123"]

    def test_published_check_is_bound_to_the_pr_head_and_actual_verdict(self):
        with patch("sys.argv", self.publish_args()), \
                patch.object(gate, "write_api", return_value={}) as write, \
                patch.object(gate, "wait_for_review", return_value=0):
            self.assertEqual(gate.main(), 0)
        start, end = write.call_args_list
        self.assertEqual(start.args[0], f"repos/o/r/statuses/{HEAD}")
        self.assertEqual(start.args[1]["state"], "pending")
        self.assertEqual(end.args[0], f"repos/o/r/statuses/{HEAD}")
        self.assertEqual(end.args[1]["state"], "success")

    def test_a_same_head_retry_clears_an_earlier_success_before_reading_metadata(self):
        status = {"state": "success"}

        def write(path, payload):
            self.assertEqual(path, f"repos/o/r/statuses/{HEAD}")
            status.update(payload)
            return {}

        def wait(args):
            self.assertEqual(status["state"], "pending")
            return 1

        with patch("sys.argv", self.publish_args()), \
                patch.object(gate, "write_api", side_effect=write), \
                patch.object(gate, "wait_for_review", side_effect=wait):
            self.assertEqual(gate.main(), 1)
        self.assertEqual(status["state"], "failure")

    def test_a_metadata_error_publishes_failure_instead_of_an_old_clean_result(self):
        with patch("sys.argv", self.publish_args()), \
                patch.object(gate, "write_api", return_value={}) as write, \
                patch.object(gate, "wait_for_review", side_effect=ValueError):
            with self.assertRaises(ValueError):
                gate.main()
        self.assertEqual(write.call_args_list[-1].args[1]["state"], "failure")

    def test_pending_write_retries_before_reading_review_metadata(self):
        error = subprocess.CalledProcessError(1, ["gh", "api"])
        with patch("sys.argv", self.publish_args()), \
                patch.object(gate, "write_api", side_effect=[error, {}, {}]) as write, \
                patch.object(gate.time, "sleep"), \
                patch.object(gate, "wait_for_review", return_value=0):
            self.assertEqual(gate.main(), 0)
        self.assertEqual([c.args[1]["state"] for c in write.call_args_list],
                         ["pending", "pending", "success"])

    def test_exhausted_pending_writes_still_attempt_to_invalidate_old_success(self):
        error = subprocess.CalledProcessError(1, ["gh", "api"])
        with patch("sys.argv", self.publish_args()), \
                patch.object(gate, "write_api", side_effect=[error, error, error, {}]) as write, \
                patch.object(gate.time, "sleep"), \
                patch.object(gate, "wait_for_review") as wait:
            with self.assertRaises(subprocess.CalledProcessError):
                gate.main()
        wait.assert_not_called()
        self.assertEqual(write.call_args_list[-1].args[1]["state"], "failure")

    def test_status_writes_use_only_the_isolated_app_token(self):
        with patch.dict(gate.os.environ, {"GH_TOKEN": "read-token",
                                        "CODEX_REVIEW_STATUS_TOKEN": "publisher-token"}), \
                patch.object(gate.subprocess, "run") as run:
            run.return_value.stdout = "{}"
            gate.write_api("repos/o/r/statuses/" + HEAD, {"state": "pending"})
        self.assertEqual(run.call_args.kwargs["env"]["GH_TOKEN"], "publisher-token")

    def test_missing_publisher_token_never_falls_back_to_actions_token(self):
        with patch.dict(gate.os.environ, {"GH_TOKEN": "read-token"}, clear=True), \
                patch.object(gate.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                gate.write_api("repos/o/r/statuses/" + HEAD, {"state": "success"})
        run.assert_not_called()

    def test_a_foreign_run_url_cannot_be_published_as_a_gate(self):
        with patch("sys.argv", self.publish_args()[:-1] + ["https://example.com"]), \
                patch("sys.stderr"), patch.object(gate, "write_api") as write:
            with self.assertRaises(SystemExit):
                gate.main()
        write.assert_not_called()


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Completion wakeups must target an open PR's current head, once per run."""
import json
import unittest
from unittest.mock import patch

import notify_cloud_pr as notify

HEAD = "a" * 40
RUN = {"name": "CI", "event": "pull_request", "status": "completed",
       "head_sha": HEAD, "conclusion": "success", "pull_requests": []}
GATE_RUN = {**RUN, "name": "Codex review gate", "event": "pull_request_target"}
PR = {"state": "open", "draft": False, "head": {"sha": HEAD}}


class CloudWakeup(unittest.TestCase):
    def run_with(self, answers):
        with patch("sys.argv", ["notify", "--repo", "o/r", "--run", "123"]), \
                patch.object(notify, "api", side_effect=answers) as api, \
                patch.object(notify.subprocess, "run") as post:
            notify.main()
            return api, post

    def test_an_empty_run_pr_list_is_resolved_by_its_exact_commit(self):
        api, post = self.run_with([RUN, [{"number": 7}], PR, []])
        self.assertIn(f"repos/o/r/commits/{HEAD}/pulls", [c.args[0] for c in api.call_args_list])
        self.assertEqual(post.call_count, 1)
        self.assertIn("repos/o/r/issues/7/comments", post.call_args.args[0])
        body = json.loads(post.call_args.kwargs["input"])["body"]
        self.assertIn(HEAD, body)
        self.assertNotIn("@codex", body)

    def test_closed_draft_or_moved_prs_do_not_receive_wakeups(self):
        for pr in [{**PR, "state": "closed"}, {**PR, "draft": True},
                   {**PR, "head": {"sha": "b" * 40}}]:
            _, post = self.run_with([RUN, [{"number": 7}], pr])
            post.assert_not_called()

    def test_a_replayed_completion_does_not_post_twice(self):
        comment = {"user": {"login": "github-actions[bot]"},
                   "body": "<!-- cloud-pr-wakeup:v1 run=123 -->\nCI complete"}
        _, post = self.run_with([RUN, [{"number": 7}], PR, [comment]])
        post.assert_not_called()

    def test_fork_run_without_commit_association_matches_repository_branch_and_sha(self):
        run = {**RUN, "head_repository": {"full_name": "fork/r"}, "head_branch": "fix"}
        exact = {**PR, "number": 7,
                 "head": {"sha": HEAD, "ref": "fix", "repo": {"full_name": "fork/r"}}}
        unrelated = [
            {**exact, "number": 8, "head": {**exact["head"], "ref": "other"}},
            {**exact, "number": 9, "head": {**exact["head"], "sha": "b" * 40}},
            {**exact, "number": 10, "head": {**exact["head"], "repo": {"full_name": "other/r"}}},
            {**exact, "number": 11, "head": {**exact["head"], "repo": None}},
        ]
        api, post = self.run_with([run, [], unrelated + [exact], exact, []])
        self.assertIn("repos/o/r/pulls?state=open&per_page=100",
                      [c.args[0] for c in api.call_args_list])
        self.assertEqual(post.call_count, 1)
        self.assertIn("repos/o/r/issues/7/comments", post.call_args.args[0])

    def test_unidentifiable_fork_run_does_not_notify_unrelated_prs(self):
        _, post = self.run_with([RUN, []])
        post.assert_not_called()

    def test_a_user_cannot_suppress_a_wakeup_with_a_copied_marker(self):
        comment = {"user": {"login": "contributor"},
                   "body": "<!-- cloud-pr-wakeup:v1 run=123 -->"}
        _, post = self.run_with([RUN, [{"number": 7}], PR, [comment]])
        self.assertEqual(post.call_count, 1)

    def test_only_each_workflows_trusted_pr_event_is_accepted(self):
        self.assertEqual(notify.targets(RUN, [{"number": 7}]), [7])
        self.assertEqual(notify.targets(GATE_RUN, [{"number": 7}]), [7])
        for run in [
            {**RUN, "event": "push"},
            {**RUN, "name": "Cloud PR wakeup"},
            {**RUN, "status": "in_progress"},
            {**RUN, "name": "Codex review gate"},
            {**GATE_RUN, "name": "CI"},
        ]:
            self.assertEqual(notify.targets(run, [{"number": 7}]), [])

    def test_target_gate_uses_its_trusted_title_not_the_base_run_sha(self):
        run = {**RUN, "name": "Codex review gate", "event": "pull_request_target",
               "head_sha": "b" * 40,
               "display_title": f"Codex review gate PR #7 @{HEAD}"}
        api, post = self.run_with([run, PR, []])
        self.assertEqual(api.call_args_list[1].args[0], "repos/o/r/pulls/7")
        self.assertIn(HEAD, json.loads(post.call_args.kwargs["input"])["body"])

    def test_target_gate_with_an_unrecognizable_title_cannot_guess_a_pr(self):
        run = {**RUN, "name": "Codex review gate", "event": "pull_request_target",
               "display_title": "PR #7 from an untrusted title"}
        with patch("sys.argv", ["notify", "--repo", "o/r", "--run", "123"]), \
                patch.object(notify, "api", return_value=run), \
                patch.object(notify.subprocess, "run") as post:
            with self.assertRaises(ValueError):
                notify.main()
        post.assert_not_called()


if __name__ == "__main__":
    unittest.main()

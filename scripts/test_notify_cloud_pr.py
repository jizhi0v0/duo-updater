#!/usr/bin/env python3
"""Completion wakeups must target an open PR's current head, once per run."""
import json
import unittest
from unittest.mock import patch

import notify_cloud_pr as notify

HEAD = "a" * 40
RUN = {"name": "CI", "event": "pull_request", "status": "completed",
       "head_sha": HEAD, "conclusion": "success", "pull_requests": []}
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

    def test_a_user_cannot_suppress_a_wakeup_with_a_copied_marker(self):
        comment = {"user": {"login": "contributor"},
                   "body": "<!-- cloud-pr-wakeup:v1 run=123 -->"}
        _, post = self.run_with([RUN, [{"number": 7}], PR, [comment]])
        self.assertEqual(post.call_count, 1)

    def test_push_runs_and_unrelated_workflows_are_not_pr_notifications(self):
        for run in [{**RUN, "event": "push"}, {**RUN, "name": "Cloud PR wakeup"},
                    {**RUN, "status": "in_progress"}]:
            self.assertEqual(notify.targets(run, [{"number": 7}]), [])


if __name__ == "__main__":
    unittest.main()

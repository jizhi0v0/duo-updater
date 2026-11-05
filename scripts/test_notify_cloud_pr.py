#!/usr/bin/env python3
"""Wakeups target an open PR's current head, once per run attempt."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import notify_cloud_pr as notify

HEAD = "a" * 40
RUN = {"name": "CI", "event": "pull_request", "status": "completed",
       "path": ".github/workflows/ci.yml",
       "run_number": 10, "head_sha": HEAD, "conclusion": "success", "pull_requests": [], "run_attempt": 1}
GATE_RUN = {**RUN, "name": f"Codex review gate PR #7 @{HEAD}",
            "path": ".github/workflows/codex-review-gate.yml", "event": "pull_request_target"}
PR = {"state": "open", "draft": False, "head": {"sha": HEAD},
      "labels": [{"name": "codex-managed"}]}


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
                   "body": "<!-- cloud-pr-wakeup:v2 run=123 attempt=1 -->\nCI complete"}
        _, post = self.run_with([RUN, [{"number": 7}], PR, [comment]])
        post.assert_not_called()

    def test_unmanaged_prs_do_not_generate_cloud_wakeup_comments(self):
        api, post = self.run_with([RUN, [{"number": 7}], {**PR, "labels": []}])
        self.assertEqual(api.call_count, 3)
        post.assert_not_called()

    def test_managed_route_remains_wakeable_after_a_later_pure_data_head(self):
        pr = {**PR, "user": {"login": "o"}, "changed_files": 1,
              "head": {"sha": HEAD, "ref": "verify/baseline-20261105T010000Z",
                       "repo": {"full_name": "o/r"}}, "base": {"sha": "b" * 40}}
        api, post = self.run_with([RUN, [{"number": 7}], pr, []])
        self.assertNotIn("/compare/", str(api.call_args_list))
        self.assertEqual(post.call_count, 1)

    def test_a_successful_rerun_wakes_after_the_first_attempts_failure(self):
        first = {"id": 80, "user": {"login": "github-actions[bot]"},
                 "body": "<!-- cloud-pr-wakeup:v2 run=123 attempt=1 -->\nCI failed"}
        run = {**RUN, "run_attempt": 2}
        _, post = self.run_with([run, [{"number": 7}], PR, [first]])
        self.assertEqual(post.call_count, 1)
        body = json.loads(post.call_args.kwargs["input"])["body"]
        self.assertIn("run=123 attempt=2", body)
        self.assertIn("**success**", body)
        second = {**first, "body": body}
        _, replay = self.run_with([run, [{"number": 7}], PR, [first, second]])
        replay.assert_not_called()

    def test_rolling_comment_writes_are_serialized_without_replacing_pending_completions(self):
        workflow = (Path(__file__).resolve().parents[1] /
                    ".github/workflows/cloud-pr-wakeup.yml").read_text()
        group = workflow.split("\nconcurrency:", 1)[1].split("\njobs:", 1)[0]
        self.assertIn("group: cloud-pr-wakeup\n", group)
        self.assertIn("cancel-in-progress: false", group)
        self.assertIn("queue: max", group)
        self.assertNotIn("workflow_run.id", group)

    def test_invalid_run_numbers_cannot_suppress_other_completions(self):
        for number in [None, 0, -1, True, "10"]:
            with self.assertRaises(ValueError):
                self.run_with([{**RUN, "run_number": number}])

    def test_invalid_attempts_do_not_publish_ambiguous_markers(self):
        for attempt in [None, 0, -1, True, "2"]:
            with self.assertRaises(ValueError):
                self.run_with([{**RUN, "run_attempt": attempt}])

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
                   "body": "<!-- cloud-pr-wakeup:v2 run=123 attempt=1 -->"}
        _, post = self.run_with([RUN, [{"number": 7}], PR, [comment]])
        self.assertEqual(post.call_count, 1)

    def test_only_each_workflows_trusted_pr_event_is_accepted(self):
        self.assertEqual(notify.targets(RUN, [{"number": 7}]), [7])
        self.assertEqual(notify.targets(GATE_RUN, [{"number": 7}]), [7])
        for run in [
            {**RUN, "event": "push"},
            {**RUN, "path": ".github/workflows/cloud-pr-wakeup.yml"},
            {**RUN, "status": "in_progress"},
            {**RUN, "event": "pull_request_target"},
            {**GATE_RUN, "event": "pull_request"},
        ]:
            self.assertEqual(notify.targets(run, [{"number": 7}]), [])

    def test_each_required_pr_workflows_failure_wakes_the_handler(self):
        for path, name in notify.PR_WORKFLOWS.items():
            run = {**RUN, "name": name, "path": path, "conclusion": "failure",
                   "pull_requests": [{"number": 7}]}
            _, post = self.run_with([run, PR, []])
            self.assertEqual(post.call_count, 1)
            body = json.loads(post.call_args.kwargs["input"])["body"]
            self.assertIn(name, body)
            self.assertIn("**failure**", body)
            self.assertEqual(notify.targets({**run, "event": "pull_request_target"}), [])

    def test_target_gate_with_dynamic_name_uses_its_trusted_title(self):
        run = {**GATE_RUN,
               "head_sha": "b" * 40,
               "display_title": f"Codex review gate PR #7 @{HEAD}"}
        api, post = self.run_with([run, PR, []])
        self.assertEqual(api.call_args_list[1].args[0], "repos/o/r/pulls/7")
        self.assertIn(HEAD, json.loads(post.call_args.kwargs["input"])["body"])

    def test_target_gate_with_an_unrecognizable_title_cannot_guess_a_pr(self):
        run = {**GATE_RUN,
               "display_title": "PR #7 from an untrusted title"}
        with patch("sys.argv", ["notify", "--repo", "o/r", "--run", "123"]), \
                patch.object(notify, "api", return_value=run), \
                patch.object(notify.subprocess, "run") as post:
            with self.assertRaises(ValueError):
                notify.main()
        post.assert_not_called()

    def test_workflow_name_cannot_disguise_an_unrelated_path(self):
        for run in [RUN, GATE_RUN]:
            _, post = self.run_with([{**run, "path": ".github/workflows/unrelated.yml"}])
            post.assert_not_called()

    def test_ref_qualified_paths_publish_for_each_supported_workflow(self):
        for path, label in notify.WORKFLOW_LABELS.items():
            run = {**(GATE_RUN if path == notify.GATE_PATH else RUN),
                   "path": path + "@refs/heads/main", "pull_requests": [{"number": 7}],
                   "display_title": f"Codex review gate PR #7 @{HEAD}"}
            _, post = self.run_with([run, PR, []])
            self.assertEqual(post.call_count, 1)
            body = json.loads(post.call_args.kwargs["input"])["body"]
            self.assertIn(label, body)
            self.assertIn("attempt 1", body)


class RollingWakeup(unittest.TestCase):
    """Exercise multiple completions against one simulated GitHub conversation."""
    def setUp(self):
        self.comments = []
        self.writes = []
        self.current_head = HEAD
        self.run = {**RUN, "id": 123, "pull_requests": [{"number": 7}]}

    def read(self, path):
        if "/actions/runs/" in path:
            return self.run
        if path == "repos/o/r/pulls/7":
            return {**PR, "head": {"sha": self.current_head}}
        if path == "repos/o/r/issues/7/comments":
            return self.comments
        self.fail(f"unexpected read: {path}")

    def write(self, command, **kwargs):
        method = command[command.index("--method") + 1]
        path = command[command.index(method) + 1]
        body = json.loads(kwargs["input"])["body"]
        self.writes.append((method, path, body))
        if method == "POST":
            self.comments.append({"id": len(self.comments) + 100,
                                  "user": {"login": "github-actions[bot]"}, "body": body})
        elif method == "PATCH":
            comment = next(c for c in self.comments if path.endswith(f"/{c['id']}"))
            comment["body"] = body
        else:
            self.fail(f"unexpected write: {method}")

    def complete(self, **changes):
        self.run = {**self.run, **changes}
        with patch("sys.argv", ["notify", "--repo", "o/r", "--run", str(self.run["id"])]), \
                patch.object(notify, "api", side_effect=self.read), \
                patch.object(notify.subprocess, "run", side_effect=self.write):
            notify.main()

    def test_different_checks_update_one_comment_and_keep_each_wakeup(self):
        self.complete()
        self.complete(id=124, run_number=5, path=".github/workflows/real-machine.yml")
        self.complete(id=125, run_number=7, path=".github/workflows/adversarial-review.yml")
        self.assertEqual(len(self.comments), 1)
        self.assertEqual([w[0] for w in self.writes], ["POST", "PATCH", "PATCH"])
        for label in ["CI", "Real-machine record", "Adversarial review record"]:
            self.assertIn(label, self.comments[0]["body"])

    def test_failure_then_successful_rerun_updates_and_wakes_without_new_comment(self):
        self.complete(conclusion="failure")
        self.complete(run_attempt=2, conclusion="success")
        self.assertEqual(len(self.comments), 1)
        self.assertEqual([w[0] for w in self.writes], ["POST", "PATCH"])
        self.assertIn("**success**", self.comments[0]["body"])
        self.complete()
        self.assertEqual(len(self.writes), 2)

    def test_replayed_earlier_check_cannot_erase_the_later_check(self):
        self.complete()
        self.complete(id=124, path=".github/workflows/real-machine.yml")
        self.complete(id=123, path=".github/workflows/ci.yml")
        self.assertEqual(len(self.writes), 2)
        self.assertIn("Real-machine record", self.comments[0]["body"])

    def test_a_late_older_run_cannot_overwrite_a_newer_failure(self):
        self.complete(id=124, run_number=11, conclusion="failure")
        self.complete(id=123, run_number=10, conclusion="success")
        self.assertEqual(len(self.writes), 1)
        self.assertIn("**failure**", self.comments[0]["body"])

    def test_a_new_head_reuses_the_comment_and_discards_old_check_results(self):
        self.complete()
        self.complete(id=124, path=".github/workflows/real-machine.yml")
        self.current_head = "b" * 40
        self.complete(id=126, run_number=12, head_sha=self.current_head,
                      path=".github/workflows/ci.yml")
        self.assertEqual(len(self.comments), 1)
        self.assertIn(self.current_head, self.comments[0]["body"])
        self.assertNotIn("Real-machine record", self.comments[0]["body"])
        self.complete(id=123, run_number=10, head_sha=HEAD)
        self.assertEqual(len(self.writes), 3)

    def test_cancellation_still_wakes_but_does_not_add_a_comment(self):
        self.complete()
        self.complete(id=124, run_number=11, conclusion="cancelled")
        self.assertEqual(len(self.comments), 1)
        self.assertEqual([w[0] for w in self.writes], ["POST", "PATCH"])
        self.assertIn("**cancelled**", self.comments[0]["body"])

    def test_legacy_bot_comment_is_reused_without_editing_human_comments(self):
        old = {"id": 80, "user": {"login": "github-actions[bot]"},
               "body": "<!-- cloud-pr-wakeup:v2 run=90 attempt=1 -->\nold"}
        human = {"id": 81, "user": {"login": "contributor"}, "body": old["body"]}
        self.comments = [old, human]
        self.complete()
        self.assertEqual(len(self.comments), 2)
        self.assertEqual(self.writes[0][:2], ("PATCH", "repos/o/r/issues/comments/80"))
        self.assertEqual(human["body"], "<!-- cloud-pr-wakeup:v2 run=90 attempt=1 -->\nold")

    def test_damaged_state_is_repaired_in_the_existing_bot_comment(self):
        self.comments = [{"id": 80, "user": {"login": "github-actions[bot]"},
                          "body": '<!-- cloud-pr-wakeup:v3 {"head":null,"checks":[]} -->'}]
        self.complete()
        self.assertEqual(len(self.comments), 1)
        self.assertEqual(self.writes[0][0], "PATCH")
        self.assertIn(HEAD, self.comments[0]["body"])


if __name__ == "__main__":
    unittest.main()

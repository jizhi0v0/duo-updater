#!/usr/bin/env python3
"""Regression tests for `ci_route`. Run by `make test`.

    python3 scripts/test_ci_route.py
"""

import io
import json
import os
import pathlib
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ci_route as cr  # noqa: E402

MINI = ["self-hosted", "duo-mini"]
HOSTED = ["xcode-27"]
LINUX = ["ubuntu-latest"]


class Choose(unittest.TestCase):
    def test_an_idle_mini_takes_the_run(self):
        runner, _ = cr.choose([("completed", MINI), ("in_progress", HOSTED)])
        self.assertEqual(runner, cr.MINI)

    def test_two_jobs_ahead_on_the_mini_is_a_tie_and_stays(self):
        # 2/2*4.3 + 6.6 = 10.9 against an idle hosted 10.9.
        runner, reason = cr.choose([("in_progress", MINI), ("queued", MINI)])
        self.assertEqual(runner, cr.MINI)
        self.assertIn("mini 2 active", reason)

    def test_jobs_over_the_hosted_slots_count_against_hosted(self):
        # 3 ahead on the mini: ~13.1. Hosted with 4 running: 4 + 3 - 5 = 2 over
        # the slots, ~13.8, so the mini. Counting only the 4 running (as if
        # this run's own three were free) would say ~10.9 and pick hosted.
        jobs = [("in_progress", MINI)] * 3 + [("in_progress", HOSTED)] * 4
        self.assertEqual(cr.choose(jobs)[0], cr.MINI)

    def test_three_jobs_ahead_on_the_mini_go_hosted(self):
        runner, reason = cr.choose([("in_progress", MINI)] * 2 + [("queued", MINI)])
        self.assertEqual(runner, cr.HOSTED)
        self.assertIn("hosted finishes first", reason)

    def test_the_queue_seen_on_2026_10_11(self):
        # Live when this was written: 7 on the mini, 3 hosted. Mini ~21.7 min,
        # hosted (1 job over the five slots) ~12.4 min.
        jobs = [("queued", MINI)] * 5 + [("in_progress", MINI)] * 2 + [("in_progress", HOSTED)] * 3
        self.assertEqual(cr.choose(jobs)[0], cr.HOSTED)

    def test_a_full_hosted_side_keeps_the_run_on_a_lightly_busy_mini(self):
        # 3 ahead on the mini (~13.1) against 10 hosted jobs (8 over: ~22.6).
        jobs = [("in_progress", MINI)] * 3 + [("queued", HOSTED)] * 10
        self.assertEqual(cr.choose(jobs)[0], cr.MINI)

    def test_linux_jobs_count_for_neither(self):
        runner, reason = cr.choose([("in_progress", LINUX)] * 10)
        self.assertEqual(runner, cr.MINI)
        self.assertIn("mini 0 active", reason)
        self.assertIn("hosted 0 active", reason)

    def test_macos_labels_count_as_hosted(self):
        self.assertTrue(cr.is_hosted_mac(["macos-15"]))
        self.assertFalse(cr.is_hosted_mac(MINI))


class Main(unittest.TestCase):
    def run_main(self, env, jobs=None, error=None):
        out, err = io.StringIO(), io.StringIO()
        def fake(repo, run):
            if error:
                raise error
            return jobs
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch.object(cr, "active_jobs", side_effect=fake), \
             redirect_stdout(out), redirect_stderr(err):
            cr.main()
        line = out.getvalue().strip()
        self.assertTrue(line.startswith("runner="), line)
        return json.loads(line.split("=", 1)[1])

    def test_everything_but_a_same_repo_pr_stays_hosted(self):
        self.assertEqual(self.run_main({"SAME_REPO_PR": "false"}, jobs=[]), cr.HOSTED)
        self.assertEqual(self.run_main({}, jobs=[]), cr.HOSTED)

    def test_a_same_repo_pr_is_routed(self):
        env = {"SAME_REPO_PR": "true", "GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "1"}
        self.assertEqual(self.run_main(env, jobs=[]), cr.MINI)
        self.assertEqual(self.run_main(env, jobs=[("in_progress", MINI)] * 3), cr.HOSTED)

    def test_a_failed_read_falls_back_to_the_mini(self):
        env = {"SAME_REPO_PR": "true", "GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "1"}
        self.assertEqual(self.run_main(env, error=RuntimeError("HTTP 502")), cr.MINI)

    def test_the_output_is_valid_for_runs_on(self):
        # fromJSON in the workflow needs a JSON array or a JSON string.
        env = {"SAME_REPO_PR": "true", "GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "1"}
        self.assertEqual(self.run_main(env, jobs=[]), ["self-hosted", "duo-mini"])
        self.assertEqual(self.run_main({"SAME_REPO_PR": "false"}, jobs=[]), "xcode-27")


if __name__ == "__main__":
    unittest.main()

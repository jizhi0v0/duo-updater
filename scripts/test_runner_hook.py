#!/usr/bin/env python3
"""Regression tests for scripts/runner-hooks/job-started.sh and the path guard of
.github/claude-review/gh-get. Run by `make test-scripts`.

    python3 scripts/test_runner_hook.py
"""

from __future__ import annotations

import json
import pathlib
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "scripts" / "runner-hooks" / "job-started.sh"
GH_GET = ROOT / ".github" / "claude-review" / "gh-get"
REPO = "jizhi0v0/duo-updater"


class JobStartedHook(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def run_hook(self, payload, event="pull_request", repo=REPO, raw=None, omit=()):
        path = self.dir / "event.json"
        path.write_text(raw if raw is not None else json.dumps(payload), encoding="utf-8")
        env = {"PATH": "/usr/bin:/bin", "GITHUB_EVENT_PATH": str(path),
               "GITHUB_EVENT_NAME": event, "GITHUB_REPOSITORY": repo}
        for key in omit:
            env.pop(key, None)
        return subprocess.run(["/bin/bash", str(HOOK)], env=env, capture_output=True,
                              text=True, timeout=30)

    def pr(self, head_repo=REPO):
        return {"pull_request": {"head": {"repo": {"full_name": head_repo}}}}

    # Allowed.
    def test_same_repository_pull_request_passes(self):
        r = self.run_hook(self.pr())
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_push_passes(self):
        r = self.run_hook({"ref": "refs/heads/main"}, event="push")
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_workflow_dispatch_passes(self):
        r = self.run_hook({}, event="workflow_dispatch")
        self.assertEqual(r.returncode, 0, r.stderr)

    # Refused.
    def test_fork_pull_request_is_refused(self):
        r = self.run_hook(self.pr("someone/duo-updater"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("someone/duo-updater", r.stderr)

    def test_pull_request_without_head_repo_is_refused(self):
        # A deleted fork has `head.repo: null`.
        for payload in ({"pull_request": {"head": {"repo": None}}},
                        {"pull_request": {"head": {}}},
                        {"pull_request": {}},
                        {}):
            self.assertNotEqual(self.run_hook(payload).returncode, 0, payload)

    def test_head_repo_without_a_string_full_name_is_refused(self):
        self.assertNotEqual(self.run_hook({"pull_request": {"head": {"repo": {}}}}).returncode, 0)
        self.assertNotEqual(
            self.run_hook({"pull_request": {"head": {"repo": {"full_name": 7}}}}).returncode, 0)

    def test_other_repository_is_refused(self):
        self.assertNotEqual(self.run_hook(self.pr("other/repo"), repo="other/repo").returncode, 0)
        self.assertNotEqual(self.run_hook({}, event="push", repo="other/repo").returncode, 0)

    def test_repository_name_is_compared_exactly(self):
        self.assertNotEqual(self.run_hook({}, event="push", repo=REPO + "-x").returncode, 0)
        self.assertNotEqual(self.run_hook({}, event="push", repo=REPO.upper()).returncode, 0)

    def test_other_events_are_refused(self):
        for event in ("pull_request_target", "issues", "issue_comment", "schedule",
                      "workflow_run", "repository_dispatch", "fork", ""):
            self.assertNotEqual(self.run_hook({}, event=event).returncode, 0, event)

    def test_missing_environment_is_refused(self):
        for name in ("GITHUB_EVENT_PATH", "GITHUB_EVENT_NAME", "GITHUB_REPOSITORY"):
            self.assertNotEqual(self.run_hook(self.pr(), omit=(name,)).returncode, 0, name)

    def test_malformed_event_file_is_refused(self):
        self.assertNotEqual(self.run_hook(None, raw="{not json").returncode, 0)
        self.assertNotEqual(self.run_hook(None, raw="[]").returncode, 0)
        self.assertNotEqual(self.run_hook(None, raw="").returncode, 0)

    def test_missing_event_file_is_refused(self):
        env = {"PATH": "/usr/bin:/bin", "GITHUB_EVENT_PATH": str(self.dir / "absent.json"),
               "GITHUB_EVENT_NAME": "pull_request", "GITHUB_REPOSITORY": REPO}
        r = subprocess.run(["/bin/bash", str(HOOK)], env=env, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)


class GhGetPathGuard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        fake = pathlib.Path(self.temp.name) / "gh"
        fake.write_text('#!/bin/sh\necho "gh called: $*"\n', encoding="utf-8")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)

    def tearDown(self):
        self.temp.cleanup()

    def run_get(self, path):
        env = {"PATH": f"{self.temp.name}:/usr/bin:/bin"}
        return subprocess.run([str(GH_GET), path], env=env, capture_output=True,
                              text=True, timeout=30)

    def test_plain_paths_reach_gh(self):
        # `%2f` stays allowed: ref names with a slash need it, and without a dot
        # it cannot climb out of repos/<owner>/<repo>.
        for path in ("repos/o/r/pulls/1", "repos/o/r/contents/a/b.txt?ref=main",
                     "repos/o/r/git/ref/heads/feature%2Fx"):
            r = self.run_get(path)
            self.assertEqual(r.returncode, 0, (path, r.stderr))
            self.assertIn("gh called", r.stdout)

    def test_literal_dot_dot_is_refused(self):
        self.assertEqual(self.run_get("repos/o/r/../../user").returncode, 64)

    def test_encoded_dots_are_refused(self):
        for path in ("repos/o/r/%2e%2e/%2e%2e/user", "repos/o/r/%2E%2E/user",
                     "repos/o/r/.%2e/user", "repos/o/r/%2e./user", "repos/o/r/a%2Eb"):
            r = self.run_get(path)
            self.assertEqual(r.returncode, 64, path)
            self.assertNotIn("gh called", r.stdout)


if __name__ == "__main__":
    unittest.main()

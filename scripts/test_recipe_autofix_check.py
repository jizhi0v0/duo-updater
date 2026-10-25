#!/usr/bin/env python3
"""The "Apply and check the change" step of recipe-autofix.yml, run for real.

That step is the allowlist gate between an autofix patch (written by a model, in
a job with no secrets) and the job that holds the PR token. It lists the paths
the patch touches and compares them to the plan's. `git diff --name-only` lists
a rename's destination only, so a patch that *renamed* a workflow into a fixture
path showed one allowed path and passed. This extracts the step's shell from the
workflow, so the gate that runs in CI is the one tested, and runs it in a
scratch repository. Run by `make test-scripts`.

    python3 scripts/test_recipe_autofix_check.py
"""

import json
import os
import pathlib
import re
import subprocess
import tempfile
import textwrap
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
WORKFLOW = REPO / ".github" / "workflows" / "recipe-autofix.yml"
STEP = "Apply and check the change"

RECIPE = "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/Foo.swift"
GOLDEN = "DuoUpdaterCore/Tests/RecipeGoldens/Foo.txt"
FIXTURE ="DuoUpdaterCore/Tests/DuoUpdaterCoreTests/Fixtures/changelog-autofix/x.txt"
WORKFLOW_IN_REPO = ".github/workflows/claude-review.yml"


def step_script():
    text = WORKFLOW.read_text()
    m = re.search(r"- name: " + re.escape(STEP) + r"\n(?:        [^\n]*\n)*?        run: \|\n"
                  r"((?:          [^\n]*\n|\n)+)", text)
    assert m, "step not found in the workflow"
    return textwrap.dedent(m.group(1))


def git(cwd, *args):
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
        cwd=cwd, check=True, capture_output=True, text=True).stdout


class ApplyAndCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = pathlib.Path(self.tmp.name)
        self.repo = root / "repo"
        self.runner_temp = root / "runner"
        (self.runner_temp / "autofix").mkdir(parents=True)
        for rel, body in [(RECIPE, "let a = 1\n"), (GOLDEN, "golden\n"),
                          (WORKFLOW_IN_REPO, "name: review\non: push\n" * 6)]:
            path = self.repo / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body)
        git(self.repo, "init", "-q")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "base")

    def run_gate(self, edit, plan_paths):
        """Builds the patch with `edit(repo)`, resets, then runs the step's shell."""
        edit(self.repo)
        git(self.repo, "add", "-A")
        patch = git(self.repo, "diff", "--cached", "-M", "--binary")
        git(self.repo, "reset", "-q", "--hard")
        git(self.repo, "clean", "-fdq")
        autofix = self.runner_temp / "autofix"
        (autofix / "change.patch").write_text(patch)
        (autofix / "pr.json").write_text(json.dumps(
            {"branch": "recipe-autofix/issue-7", "paths": plan_paths}))
        return subprocess.run(
            ["bash", "-c", step_script()], cwd=self.repo, capture_output=True, text=True,
            env={**os.environ, "RUNNER_TEMP": str(self.runner_temp), "ISSUE": "7"})

    def test_a_recipe_edit_with_a_fixture_passes(self):
        def edit(repo):
            (repo / RECIPE).write_text("let a = 2\n")
            fixture = repo / FIXTURE
            fixture.parent.mkdir(parents=True)
            fixture.write_text("sample\n")
        result = self.run_gate(edit, [RECIPE, FIXTURE])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("paths ok", result.stdout)

    def test_renaming_a_workflow_into_a_fixture_path_is_refused(self):
        # The plan lists only the destination, as the rename's diff does without
        # --no-renames. The deleted workflow is the part nobody was looking at.
        def edit(repo):
            (repo / RECIPE).write_text("let a = 2\n")
            fixture = repo / FIXTURE
            fixture.parent.mkdir(parents=True)
            (repo / WORKFLOW_IN_REPO).rename(fixture)
        result = self.run_gate(edit, [RECIPE, FIXTURE])
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(WORKFLOW_IN_REPO, result.stderr)

    def test_deleting_an_allowed_path_is_refused(self):
        # Only additions and modifications are something an autofix does.
        def edit(repo):
            (repo / RECIPE).write_text("let a = 2\n")
            (repo / GOLDEN).unlink()
        result = self.run_gate(edit, [RECIPE, GOLDEN])
        self.assertNotEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Exercise the actual issue-step shell block without GitHub or network access."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/install-verify.yml"
STEP_NAME = "      - name: File and close issues"


def extract_issue_step_run_block() -> str:
    lines = WORKFLOW.read_text(encoding="utf-8").splitlines()
    try:
        step_start = lines.index(STEP_NAME)
    except ValueError as error:
        raise AssertionError("workflow File and close issues step was not found") from error

    run_header = "        run: |"
    try:
        run_start = lines.index(run_header, step_start + 1)
    except ValueError as error:
        raise AssertionError("issue step's literal run block was not found") from error

    command_lines = []
    for line in lines[run_start + 1 :]:
        if line.strip() and len(line) - len(line.lstrip(" ")) < 10:
            break
        command_lines.append(line[10:] if line.startswith("          ") else "")
    if not command_lines or not any(line.strip() for line in command_lines):
        raise AssertionError("issue step's run block is empty")
    return "\n".join(command_lines).rstrip() + "\n"


class InstallVerifyWorkflowRunBlockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.run_block = extract_issue_step_run_block()

    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.fake_cli = self.root / "CLI/.build/debug/duo"
        self.fake_cli.parent.mkdir(parents=True)
        self.fake_cli.write_text("#!/bin/sh\nexit \"$FAKE_RECONCILE_STATUS\"\n", encoding="utf-8")
        self.fake_cli.chmod(0o755)
        self.output = self.root / "github-output.txt"
        self.output.touch()

    def tearDown(self):
        self.tempdir.cleanup()

    def run_step(self, status, output_path=None):
        environment = os.environ.copy()
        environment["FAKE_RECONCILE_STATUS"] = str(status)
        environment["GITHUB_OUTPUT"] = str(output_path or self.output)
        return subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", self.run_block],
            cwd=self.root,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_status_zero_output_write_failure_fails_the_step(self):
        result = self.run_step(0, Path("/dev/null/receipt"))

        self.assertNotEqual(result.returncode, 0, result.stderr)

    def test_status_zero_writes_a_receipt_and_succeeds(self):
        result = self.run_step(0)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "exit_code=0\n")

    def test_status_one_writes_a_receipt_and_preserves_failure(self):
        result = self.run_step(1)

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "exit_code=1\n")

    def test_status_two_writes_a_receipt_and_preserves_operational_failure(self):
        result = self.run_step(2)

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.output.read_text(encoding="utf-8"), "exit_code=2\n")


if __name__ == "__main__":
    unittest.main()

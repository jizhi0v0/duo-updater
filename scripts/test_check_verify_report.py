#!/usr/bin/env python3
"""Tests for the nightly verify-report freshness gate."""

import datetime as dt
import json
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_verify_report.py")


def finding(recipe_id, status="ok", registry="vendor"):
    return {
        "recipeID": recipe_id,
        "registry": registry,
        "bundleID": "com.example." + recipe_id.rsplit(".", 1)[-1],
        "channel": "-",
        "status": status,
        "warnings": [],
        "endpointHost": "updates.example.com",
        "attempts": 1,
        "elapsedMs": 10,
    }


def generated_at(epoch):
    return dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).isoformat().replace(
        "+00:00", "Z"
    )


class CheckVerifyReportTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.path = Path(self.tempdir.name) / "findings.json"

    def tearDown(self):
        self.tempdir.cleanup()

    def write_document(self, document):
        self.path.write_text(json.dumps(document), encoding="utf-8")

    def run_validator(self, not_before):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.path), "--not-before", str(not_before)],
            capture_output=True,
            text=True,
            check=False,
        )

    def document(self, epoch, findings=None):
        return {
            "schemaVersion": 1,
            "generatedAt": generated_at(epoch),
            "findings": findings if findings is not None else [finding("vendor:example")],
        }

    def test_accepts_fresh_actionable_and_skipped_rows_in_same_second(self):
        started_at = int(time.time())
        self.write_document(self.document(started_at, [
            finding("vendor:example.actionable", status="warn"),
            finding("install:example.skipped", status="skipped", registry="install"),
        ]))

        result = self.run_validator(started_at)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2 findings", result.stdout)

    def test_rejects_a_stale_report(self):
        started_at = int(time.time())
        self.write_document(self.document(started_at - 1))

        result = self.run_validator(started_at)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stale", result.stderr)

    def test_rejects_malformed_or_truncated_json(self):
        self.path.write_text('{"schemaVersion":1,"findings":[', encoding="utf-8")

        result = self.run_validator(int(time.time()))

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not valid JSON", result.stderr)

    def test_rejects_an_empty_findings_array(self):
        self.write_document(self.document(int(time.time()), []))

        result = self.run_validator(0)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-empty", result.stderr)

    def test_rejects_duplicate_recipe_ids(self):
        row = finding("vendor:example.duplicate")
        self.write_document(self.document(int(time.time()), [row, dict(row)]))

        result = self.run_validator(0)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate recipe IDs", result.stderr)

    def test_rejects_duplicate_json_keys(self):
        self.path.write_text(
            '{"schemaVersion":1,"schemaVersion":1,'
            '"generatedAt":"2026-11-15T00:00:00Z",'
            '"findings":[{}]}',
            encoding="utf-8",
        )

        result = self.run_validator(0)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate JSON object key", result.stderr)

    def test_rejects_unsupported_schema_and_status_values(self):
        unsupported_schema = self.document(int(time.time()))
        unsupported_schema["schemaVersion"] = 2
        self.write_document(unsupported_schema)
        self.assertNotEqual(self.run_validator(0).returncode, 0)

        unsupported_status = self.document(
            int(time.time()), [finding("vendor:example.bad", status="healthy")]
        )
        self.write_document(unsupported_status)
        result = self.run_validator(0)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported status", result.stderr)

    def test_rejects_missing_required_finding_fields(self):
        row = finding("vendor:example.missing")
        del row["endpointHost"]
        self.write_document(self.document(int(time.time()), [row]))

        result = self.run_validator(0)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("endpointHost", result.stderr)

    def test_validation_errors_do_not_echo_vendor_payloads(self):
        secret = "https://updates.example.com/file?token=do-not-print"
        row = finding("vendor:example.invalid", status="unknown")
        row["failureDetail"] = secret
        self.write_document(self.document(int(time.time()), [row]))

        result = self.run_validator(0)

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(secret, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Regression tests for scripts/claude-lag-probe.sh."""

from __future__ import annotations

import base64
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import textwrap
import unittest


SCRIPT = pathlib.Path(__file__).with_name("claude-lag-probe.sh")


class ClaudeLagProbeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.probe_dir = self.root / "probe state"
        self.probe_dir.mkdir()
        self.did_file = self.root / "ant-did"
        self.did_file.write_bytes(base64.b64encode(b"fixture-device"))

        self.fake_curl = self.root / "fake-curl"
        self.fake_curl.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json
                import os
                import sys

                args = " ".join(sys.argv[1:])
                if "latest/redirect" in args:
                    ga = os.environ.get("FIXTURE_GA", "")
                    if ga:
                        print(f"Location: https://downloads.example/universal/{ga}/Claude.zip")
                    print(f"CODE={os.environ.get('FIXTURE_CODE', '200')} "
                          f"IP={os.environ.get('FIXTURE_IP', '203.0.113.8')}")
                elif "squirrel/update" in args:
                    rollout = os.environ.get("FIXTURE_ROLLOUT", "")
                    body = {}
                    if rollout:
                        body["currentRelease"] = rollout
                        body["pub_date"] = "2026-09-02"
                    print(json.dumps(body, separators=(",", ":")))
                else:
                    raise SystemExit(f"unexpected curl invocation: {args}")
                """
            ),
            encoding="utf-8",
        )
        self.fake_curl.chmod(self.fake_curl.stat().st_mode | stat.S_IXUSR)

    def tearDown(self) -> None:
        self.temp.cleanup()

    @property
    def state(self) -> pathlib.Path:
        return self.probe_dir / ".last"

    def run_probe(self, ga: str, rollout: str, code: str = "200") -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "CLAUDE_LAG_PROBE_DIR": str(self.probe_dir),
                "CLAUDE_LAG_DID_FILE": str(self.did_file),
                "CLAUDE_LAG_CURL": str(self.fake_curl),
                "FIXTURE_GA": ga,
                "FIXTURE_ROLLOUT": rollout,
                "FIXTURE_CODE": code,
            }
        )
        subprocess.run(["/bin/bash", str(SCRIPT)], env=env, check=True)
        lines = (self.probe_dir / "claude-lag.jsonl").read_text(encoding="utf-8").splitlines()
        return json.loads(lines[-1])

    def test_missing_ga_is_partial_and_does_not_replace_state(self) -> None:
        self.state.write_text("1.0|1.0", encoding="utf-8")
        event = self.run_probe(ga="", rollout="2.0")

        self.assertEqual(event["event"], "partial")
        self.assertEqual(event["ga"], "")
        self.assertEqual(event["rollout"], "2.0")
        self.assertEqual(self.state.read_text(encoding="utf-8"), "1.0|1.0")

    def test_missing_rollout_is_partial_and_does_not_replace_state(self) -> None:
        self.state.write_text("1.0|1.0", encoding="utf-8")
        event = self.run_probe(ga="2.0", rollout="")

        self.assertEqual(event["event"], "partial")
        self.assertEqual(event["ga"], "2.0")
        self.assertEqual(event["rollout"], "")
        self.assertEqual(self.state.read_text(encoding="utf-8"), "1.0|1.0")

    def test_two_missing_values_remain_unreachable(self) -> None:
        self.state.write_text("1.0|1.0", encoding="utf-8")
        event = self.run_probe(ga="", rollout="")

        self.assertEqual(event["event"], "unreachable")
        self.assertEqual(self.state.read_text(encoding="utf-8"), "1.0|1.0")

    def test_complete_pair_records_a_real_change_from_last_complete_pair(self) -> None:
        self.state.write_text("1.0|1.0", encoding="utf-8")
        self.run_probe(ga="", rollout="2.0")
        event = self.run_probe(ga="2.0", rollout="2.0")

        self.assertEqual(event["event"], "change")
        self.assertEqual(event["prev"], "1.0|1.0")
        self.assertEqual(self.state.read_text(encoding="utf-8"), "2.0|2.0")


if __name__ == "__main__":
    unittest.main()

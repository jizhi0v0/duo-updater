#!/usr/bin/env python3
"""Require the exact successful CI jobs for the selected validation mode."""
import json
import os


def passed(results, nightly=False, bench=False):
    expected = {"route": "success", "swift": "success", "app": "success",
                "release": "success", "ifchange": "success", "nightly-data": "skipped"}
    if nightly or bench:
        expected.update({name: "skipped" for name in ("swift", "app", "release")})
    if nightly:
        expected.update({"ifchange": "skipped", "nightly-data": "success"})
    return all(results.get(name, {}).get("result") == value for name, value in expected.items())


if __name__ == "__main__":
    raise SystemExit(0 if passed(json.loads(os.environ["NEEDS"]),
                                os.environ.get("NIGHTLY_ONLY") == "true",
                                os.environ.get("BENCH_ONLY") == "true") else 1)

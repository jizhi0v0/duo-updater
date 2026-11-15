#!/usr/bin/env python3
"""Reject stale or structurally incomplete Duo verify findings reports.

This intentionally validates the existing `Report.Document` schema rather than
introducing a workflow-specific report format. Keep SCHEMA_VERSION in sync with
`DocumentSchemaVersion.current` in CLI/Sources/DuoKit/Report.swift.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any, Optional


SCHEMA_VERSION = 1
REGISTRIES = {
    "vendor",
    "github",
    "changelog",
    "appstore",
    "feed",
    "mygo",
    "pkgarch",
    "coverage",
    "install",
}
STATUSES = {"ok", "warn", "broken", "infra", "skipped"}
REQUIRED_FINDING_FIELDS = {
    "recipeID": str,
    "registry": str,
    "bundleID": str,
    "channel": str,
    "status": str,
    "warnings": list,
    "endpointHost": str,
    "attempts": int,
    "elapsedMs": int,
}


class ReportError(ValueError):
    pass


class DuplicateKeyError(ReportError):
    pass


def _object_without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError("duplicate JSON object key")
        result[key] = value
    return result


def _reject_non_json_constant(_: str) -> None:
    raise ReportError("non-standard JSON constant")


def _parse_generated_at(value: Any) -> dt.datetime:
    if not isinstance(value, str) or not value:
        raise ReportError("generatedAt must be an ISO-8601 timestamp")
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError as error:
        raise ReportError("generatedAt must be an ISO-8601 timestamp") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ReportError("generatedAt must include a timezone")
    return parsed.astimezone(dt.timezone.utc)


def _validate_finding(finding: Any, index: int) -> str:
    if not isinstance(finding, dict):
        raise ReportError(f"finding {index} must be an object")
    for field, expected_type in REQUIRED_FINDING_FIELDS.items():
        value = finding.get(field)
        if not isinstance(value, expected_type) or (
            expected_type is str and not value.strip()
        ):
            raise ReportError(f"finding {index} has an invalid {field}")

    # `bool` is a subclass of `int` in Python, but Swift encodes these as integers.
    for field in ("attempts", "elapsedMs"):
        value = finding[field]
        if isinstance(value, bool) or value < 0:
            raise ReportError(f"finding {index} has an invalid {field}")

    if finding["registry"] not in REGISTRIES:
        raise ReportError(f"finding {index} has an unsupported registry")
    if finding["status"] not in STATUSES:
        raise ReportError(f"finding {index} has an unsupported status")
    if any(not isinstance(warning, str) for warning in finding["warnings"]):
        raise ReportError(f"finding {index} has an invalid warnings list")
    return finding["recipeID"]


def validate_report(path: Path, not_before: int) -> int:
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ReportError("report is missing or unreadable") from error

    try:
        document = json.loads(
            raw,
            object_pairs_hook=_object_without_duplicate_keys,
            parse_constant=_reject_non_json_constant,
        )
    except (json.JSONDecodeError, DuplicateKeyError, ReportError) as error:
        if isinstance(error, DuplicateKeyError):
            raise
        raise ReportError("report is not valid JSON") from error

    if not isinstance(document, dict):
        raise ReportError("report root must be an object")
    version = document.get("schemaVersion")
    if (
        isinstance(version, bool)
        or not isinstance(version, int)
        or version != SCHEMA_VERSION
    ):
        raise ReportError("report schemaVersion is missing or unsupported")

    generated_at = _parse_generated_at(document.get("generatedAt"))
    if int(generated_at.timestamp()) < not_before:
        raise ReportError("report is stale")

    findings = document.get("findings")
    if not isinstance(findings, list) or not findings:
        raise ReportError("report findings must be a non-empty array")

    seen: set[str] = set()
    for index, finding in enumerate(findings):
        recipe_id = _validate_finding(finding, index)
        if recipe_id in seen:
            raise ReportError("report contains duplicate recipe IDs")
        seen.add(recipe_id)
    return len(findings)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--not-before", type=int, required=True, metavar="EPOCH_SECONDS")
    args = parser.parse_args(argv)

    try:
        count = validate_report(args.report, args.not_before)
    except ReportError as error:
        print(f"invalid verify report: {error}", file=sys.stderr)
        return 1
    print(f"validated verify report ({count} findings)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

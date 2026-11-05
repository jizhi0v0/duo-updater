#!/usr/bin/env python3
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import check_nightly_data as data

BASE, HEAD, MERGE = "b" * 40, "a" * 40, "c" * 40
PATH = "verify/baseline.json"
REPO = {"full_name": "o/r", "default_branch": "main"}
PR = {"number": 7, "user": {"login": "o"}, "changed_files": 1,
      "head": {"sha": HEAD, "ref": "verify/baseline-20261105T010000Z", "repo": REPO},
      "base": {"sha": BASE, "ref": "main"}}
FILES = [{"filename": PATH, "status": "modified"}]
STAMP = "2026-11-05T01:00:00Z"


def baseline():
    return {"schemaVersion": 1, "updatedAt": STAMP,
            "entries": {"vendor:app": {field: 0 for field in data.COUNTERS}}}


def identities():
    return {"schemaVersion": 1, "lastFullPassAt": STAMP,
            "entries": {"vendor:app": {"architectures": ["arm64"],
                        "teamIdentifier": "EXAMPLETEAM", "bundleIdentifier": "com.example.app",
                        "firstSeenAt": STAMP, "firstSeenVersion": "1.0", "lastSeenAt": STAMP,
                        "lastSeenVersion": "1.0", "lastSeenURLSHA256": "a" * 64}}}


def nightly_pr(kind="baseline"):
    return {"state": "open", "draft": False, "user": {"login": "o"},
            "head": {"sha": HEAD, "ref": f"verify/{kind}-20261105T010000Z",
                     "repo": {"full_name": "o/r"}},
            "base": {"sha": BASE}, "changed_files": 1}


def changed(path, **extra):
    return {"filename": path, "status": "modified", **extra}


class NightlyClassification(unittest.TestCase):
    def test_only_the_owners_timestamped_same_repo_scan_branches_qualify(self):
        pr = nightly_pr()
        self.assertTrue(data.is_nightly_state(pr, "o/r", [changed("verify/baseline.json")]))
        for candidate in [
            {**pr, "user": {"login": "someone-else"}},
            {**pr, "head": {**pr["head"], "repo": {"full_name": "fork/r"}}},
            {**pr, "head": {**pr["head"], "repo": None}},
            {**pr, "head": {**pr["head"], "ref": "verify/baseline-custom"}},
            {**pr, "head": {**pr["head"], "ref": "feature/change"}},
        ]:
            self.assertFalse(data.is_nightly_state(candidate, "o/r", [changed("verify/baseline.json")]))

    def test_install_scan_may_change_one_or_both_state_files(self):
        pr = nightly_pr("install")
        files = [changed("verify/identities.json"), changed("verify/install-baseline.json")]
        for subset in [files[:1], files[1:], files]:
            self.assertTrue(data.is_nightly_state({**pr, "changed_files": len(subset)}, "o/r", subset))

    def test_extra_deleted_renamed_or_incomplete_files_prevent_the_exception(self):
        pr = nightly_pr()
        for files, count in [
            ([], 0),
            ([changed("verify/baseline.json"), changed("CLI/Sources/Example.swift")], 2),
            ([changed("verify/identities.json")], 1),
            ([changed("verify/baseline.json", status="removed")], 1),
            ([changed("verify/baseline.json", status="renamed", previous_filename="code.swift")], 1),
            ([changed("verify/baseline.json")], 2),
            ([changed("verify/baseline.json")], True),
        ]:
            self.assertFalse(data.is_nightly_state({**pr, "changed_files": count}, "o/r", files))


class Routing(unittest.TestCase):
    def test_pr_plan_uses_the_actual_fixed_head_and_shared_exemption(self):
        event = {"repository": REPO, "number": 7, "pull_request": PR}
        with patch.object(data, "api", side_effect=[PR, {"files": FILES, "merge_base_commit": {"sha": BASE}}]) as api:
            self.assertEqual(data.plan("o/r", "pull_request", event, HEAD),
                             {"base": BASE, "head": HEAD, "files": [PATH]})
        self.assertEqual(api.call_args_list[-1].args[0], f"repos/o/r/compare/{BASE}...{HEAD}")
        for pr, files in [
            ({**PR, "head": {**PR["head"], "sha": MERGE}}, FILES),
            ({**PR, "head": {**PR["head"], "repo": {"full_name": "fork/r"}}}, FILES),
            ({**PR, "changed_files": 2}, FILES + [{"filename": "scripts/evil.py", "status": "modified"}]),
            ({**PR, "changed_files": 2}, FILES),
        ]:
            with patch.object(data, "api", side_effect=[pr, {"files": files, "merge_base_commit": {"sha": BASE}}]):
                self.assertIsNone(data.plan("o/r", "pull_request", event, HEAD))

    def test_unrelated_main_updates_are_not_treated_as_changes_by_the_pr(self):
        tip = "d" * 40
        pr = {**PR, "base": {"sha": tip, "ref": "main"}}
        event = {"repository": REPO, "number": 7, "pull_request": pr}
        with patch.object(data, "api", side_effect=[pr, {"files": FILES, "merge_base_commit": {"sha": BASE}}]) as api:
            self.assertEqual(data.plan("o/r", "pull_request", event, HEAD)["base"], BASE)
        self.assertEqual(api.call_args_list[-1].args[0], f"repos/o/r/compare/{tip}...{HEAD}")

    def test_merged_main_push_uses_push_range_and_fetches_full_pr_metadata(self):
        event = {"repository": REPO, "ref": "refs/heads/main", "before": BASE, "after": MERGE}
        merged = {**PR, "merged": True, "merged_at": STAMP, "merge_commit_sha": MERGE}
        summary = {k: v for k, v in merged.items() if k != "changed_files"}
        comparison = {"files": FILES, "merge_base_commit": {"sha": BASE}}
        with patch.object(data, "api", side_effect=[[summary], merged, comparison]) as api:
            self.assertEqual(data.plan("o/r", "push", event, MERGE),
                             {"base": BASE, "head": MERGE, "files": [PATH]})
        self.assertEqual(api.call_args_list[1].args[0], "repos/o/r/pulls/7")
        self.assertEqual(api.call_args_list[-1].args[0], f"repos/o/r/compare/{BASE}...{MERGE}")
        for comparison in [
            {"files": FILES, "merge_base_commit": {"sha": HEAD}},
            {"files": FILES + [{"filename": "App/project.yml", "status": "modified"}],
             "merge_base_commit": {"sha": BASE}},
        ]:
            with patch.object(data, "api", side_effect=[[summary], merged, comparison]):
                self.assertIsNone(data.plan("o/r", "push", event, MERGE))

    def test_dispatch_non_main_push_and_non_scan_merge_never_skip_full_ci(self):
        event = {"repository": REPO, "ref": "refs/heads/feature", "before": BASE, "after": MERGE}
        with patch.object(data, "api") as api:
            self.assertIsNone(data.plan("o/r", "workflow_dispatch", event, MERGE))
            self.assertIsNone(data.plan("o/r", "push", event, MERGE))
            api.assert_not_called()
        event["ref"] = "refs/heads/main"
        for candidates in [[], [{**PR, "merged_at": STAMP, "merge_commit_sha": MERGE,
                                "head": {**PR["head"], "ref": "feature/fix"}}]]:
            with patch.object(data, "api", return_value=candidates):
                self.assertIsNone(data.plan("o/r", "push", event, MERGE))


class Documents(unittest.TestCase):
    def test_duplicate_keys_nonfinite_numbers_and_bad_utf8_are_rejected(self):
        for raw in [b'{"entries":{},"entries":{}}', b'{"n":NaN}', b'{"n":Infinity}', b'\xff']:
            with self.assertRaises(ValueError):
                data.decode(raw)

    def test_baselines_reject_corrupt_types_dates_counters_and_total_reset(self):
        old = baseline()
        changes = []
        for field, value in [("schemaVersion", 2), ("schemaVersion", True),
                             ("entries", []), ("entries", {}), ("updatedAt", "yesterday"),
                             ("updatedAt", "2026-11-04T01:00:00Z")]:
            new = copy.deepcopy(old)
            new[field] = value
            changes.append(new)
        for field, value in [("consecutiveInfra", -1), ("consecutiveInfra", True),
                             ("consecutiveInfra", 2**63), ("issueNumber", 0),
                             ("lastGoodAt", "2026-02-30T00:00:00Z"), ("lastGoodVersion", 1)]:
            new = copy.deepcopy(old)
            new["entries"]["vendor:app"][field] = value
            changes.append(new)
        for path in [PATH, "verify/install-baseline.json"]:
            data.validate_document(path, old, old)
            for new in changes:
                with self.assertRaises(ValueError):
                    data.validate_document(path, new, old)

    def test_pruning_and_observed_version_changes_do_not_require_model_judgment(self):
        old = identities()
        old["entries"]["retired"] = copy.deepcopy(old["entries"]["vendor:app"])
        new = identities()
        new["entries"]["vendor:app"].update(lastSeenVersion="0.9", lastSeenURLSHA256="b" * 64)
        new["entries"]["new-app"] = copy.deepcopy(new["entries"]["vendor:app"])
        data.validate_document("verify/identities.json", new, old)

    def test_existing_trust_and_provenance_cannot_be_rewritten_by_a_scan(self):
        old = identities()
        for field, value in [("teamIdentifier", "OTHER"), ("bundleIdentifier", "other.app"),
                             ("sparklePublicKey", "new-key"), ("firstSeenVersion", "0.9"),
                             ("architectures", []), ("lastSeenAt", "2026-11-04T01:00:00Z"),
                             ("firstSeenAt", "2026-11-04T01:00:00Z"), ("lastSeenURLSHA256", "bad"),
                             ("lastSeenURL", "https://example.com/?token=secret")]:
            new = copy.deepcopy(old)
            new["entries"]["vendor:app"][field] = value
            with self.assertRaises(ValueError):
                data.validate_document("verify/identities.json", new, old)
        for value in [None, "2026-11-04T01:00:00Z"]:
            with self.assertRaises(ValueError):
                data.validate_document("verify/identities.json", {**old, "lastFullPassAt": value}, old)

    def test_actual_committed_snapshots_match_the_validator(self):
        root = Path(__file__).resolve().parent.parent
        for path in data.STATE_FILES:
            doc = data.decode((root / path).read_bytes())
            data.validate_document(path, doc, doc)

    def test_raw_git_blob_reader_rejects_a_symlink_instead_of_following_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            def git(*args):
                return subprocess.run(["git", "-C", tmp, *args], check=True,
                                      capture_output=True).stdout

            git("init", "-q")
            (root / "verify").mkdir()
            (root / PATH).write_text(json.dumps(baseline()))
            git("add", ".")
            git("-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-qm", "data")
            sha = git("rev-parse", "HEAD").decode().strip()
            with patch.object(data, "git", side_effect=git):
                self.assertEqual(data.read_document(sha, PATH), baseline())
            (root / PATH).unlink()
            (root / PATH).symlink_to("/etc/passwd")
            git("add", ".")
            git("-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-qm", "symlink")
            sha = git("rev-parse", "HEAD").decode().strip()
            with patch.object(data, "git", side_effect=git), self.assertRaises(ValueError):
                data.read_document(sha, PATH)


if __name__ == "__main__":
    unittest.main()

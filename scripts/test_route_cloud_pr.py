#!/usr/bin/env python3
import json
import unittest
from unittest.mock import patch

import route_cloud_pr as router

HEAD, BASE = "a" * 40, "b" * 40
PR = {"state": "open", "head": {"sha": HEAD, "ref": "feature/fix", "repo": {"full_name": "o/r"}},
      "base": {"sha": BASE, "ref": "main"}, "changed_files": 1,
      "user": {"login": "o"}, "labels": []}
SCAN = {**PR, "head": {**PR["head"], "ref": "verify/baseline-20261105T010000Z"}}
DIFF = {"files": [{"filename": "verify/baseline.json", "status": "modified"}]}


class Routing(unittest.TestCase):
    def run_with(self, answers, apply=True, removed_label=None):
        args = ["route", "--repo", "o/r", "--pr", "7", "--head", HEAD]
        if removed_label is not None:
            args += ["--removed-label", removed_label]
        with patch("sys.argv", args + (["--apply"] if apply else [])), \
                patch.object(router, "api", side_effect=answers) as api, \
                patch.object(router.subprocess, "run") as write:
            router.main()
            return api, write

    def test_normal_pr_gets_the_cloud_trigger_label(self):
        _, write = self.run_with([PR, PR])
        self.assertEqual(write.call_count, 1)
        self.assertEqual(json.loads(write.call_args.kwargs["input"]), {"labels": [router.MANAGED]})

    def test_pure_scan_gets_only_the_informational_data_label(self):
        api, write = self.run_with([SCAN, DIFF, SCAN])
        self.assertEqual(api.call_args_list[1].args[0], f"repos/o/r/compare/{BASE}...{HEAD}")
        self.assertEqual(write.call_count, 1)
        self.assertEqual(json.loads(write.call_args.kwargs["input"]), {"labels": [router.DATA_ONLY]})

    def test_adding_code_to_a_scan_branch_restores_cloud_handling(self):
        pr = {**SCAN, "changed_files": 2, "labels": [{"name": router.DATA_ONLY}, {"name": "needs-real-machine"}]}
        diff = {"files": DIFF["files"] + [{"filename": "CLI/Sources/Fix.swift", "status": "modified"}]}
        _, write = self.run_with([pr, diff, pr])
        self.assertEqual(write.call_count, 2)
        self.assertTrue(write.call_args_list[0].args[0][-1].endswith("/labels/" + router.DATA_ONLY))
        self.assertEqual(json.loads(write.call_args_list[1].kwargs["input"]), {"labels": [router.MANAGED]})
        self.assertNotIn("needs-real-machine", str(write.call_args_list))

    def test_managed_route_is_sticky_across_a_later_pure_data_head(self):
        pr = {**SCAN, "labels": [{"name": router.MANAGED}, {"name": "needs-real-machine"}]}
        api, write = self.run_with([pr, pr])
        self.assertEqual(api.call_count, 2)
        self.assertNotIn("/compare/", str(api.call_args_list))
        write.assert_not_called()

    def test_managed_added_while_classifying_prevents_a_stale_downgrade(self):
        pr = {**SCAN, "labels": [{"name": router.DATA_ONLY}, {"name": "needs-real-machine"}]}
        current = {**SCAN, "labels": pr["labels"] + [{"name": router.MANAGED}]}
        api, write = self.run_with([pr, DIFF, current])
        self.assertEqual(api.call_count, 3)
        self.assertEqual(write.call_count, 1)
        self.assertTrue(write.call_args.args[0][-1].endswith("/labels/" + router.DATA_ONLY))
        self.assertNotIn("needs-real-machine", str(write.call_args_list))

    def test_removing_managed_restores_it_instead_of_downgrading_the_pr(self):
        pr = {**SCAN, "labels": [{"name": "needs-real-machine"}]}
        api, write = self.run_with([pr, pr], removed_label=router.MANAGED)
        self.assertEqual(api.call_count, 2)
        self.assertNotIn("/compare/", str(api.call_args_list))
        self.assertEqual(write.call_count, 1)
        self.assertEqual(json.loads(write.call_args.kwargs["input"]), {"labels": [router.MANAGED]})
        self.assertNotIn("needs-real-machine", str(write.call_args_list))

    def test_already_classified_events_do_not_write_labels_again(self):
        pr = {**SCAN, "labels": [{"name": router.DATA_ONLY}]}
        _, write = self.run_with([pr, DIFF, pr])
        write.assert_not_called()

    def test_closed_or_superseded_heads_cannot_change_labels(self):
        for pr in [{**PR, "state": "closed"}, {**PR, "head": {**PR["head"], "sha": BASE}}]:
            _, write = self.run_with([pr])
            write.assert_not_called()
        api, write = self.run_with([SCAN, DIFF, {**SCAN, "head": {**SCAN["head"], "sha": BASE}}])
        self.assertEqual(api.call_count, 3)
        write.assert_not_called()

    def test_changed_comparison_metadata_prevents_label_writes(self):
        with self.assertRaises(ValueError):
            self.run_with([SCAN, DIFF, {**SCAN, "changed_files": 2}])

    def test_unrelated_repo_metadata_does_not_invalidate_a_fixed_comparison(self):
        current = {**SCAN, "base": {**SCAN["base"], "repo": {"pushed_at": "now"}}}
        _, write = self.run_with([SCAN, DIFF, current])
        self.assertEqual(write.call_count, 1)

    def test_preview_does_not_apply_labels(self):
        _, write = self.run_with([SCAN, DIFF, SCAN], apply=False)
        write.assert_not_called()


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
import unittest
from check_ci_results import passed


class Results(unittest.TestCase):
    def test_each_mode_requires_its_actual_checks_and_rejects_failed_or_missing_jobs(self):
        full = {name: {"result": "success"} for name in ("route", "swift", "app", "release", "ifchange")}
        full["nightly-data"] = {"result": "skipped"}
        bench = {**full, **{name: {"result": "skipped"} for name in ("swift", "app", "release")}}
        nightly = {**bench, "ifchange": {"result": "skipped"}, "nightly-data": {"result": "success"}}
        for results, is_nightly, is_bench in [(full, False, False), (bench, False, True), (nightly, True, False)]:
            self.assertTrue(passed(results, is_nightly, is_bench))
            for name, result in results.items():
                self.assertFalse(passed({k: v for k, v in results.items() if k != name}, is_nightly, is_bench))
                if result["result"] == "success":
                    for state in ["failure", "cancelled", "skipped"]:
                        self.assertFalse(passed({**results, name: {"result": state}}, is_nightly, is_bench))

    def test_a_data_success_cannot_replace_a_normal_build_without_the_classification(self):
        results = {name: {"result": "skipped"} for name in ("swift", "app", "release", "ifchange")}
        results.update({"route": {"result": "success"}, "nightly-data": {"result": "success"}})
        self.assertFalse(passed(results))


if __name__ == "__main__":
    unittest.main()

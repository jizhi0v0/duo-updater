import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ci_mini_reuse import REPO, WORKFLOW, main, source_run
from ci_release_inputs import validate_feed, validate_metadata
from check_ci_results import passed


class Evidence(unittest.TestCase):
    def setUp(self):
        self.tree, self.commit, self.head = (c * 40 for c in "abc")
        self.platform = "1" * 64
        self.run = dict(id=321, path=WORKFLOW, head_repository={"full_name": REPO}, head_sha=self.head,
                        actor={"login": "jizhi0v0"}, event="pull_request", conclusion="success", run_attempt=1)
        self.record = f"Full mini CI {self.commit} {self.tree} {self.platform}"
        self.jobs = {n: "success" for n in ("swift", "app", "release", "ifchange", "test", self.record)}
        self.parents = [{"sha": self.tree}, {"sha": self.head}]
        self.workflow_blob = "expected"

    def lookup(self, path):
        if path.startswith("actions/workflows/"):
            return {"workflow_runs": [self.run]}
        if path.startswith("actions/runs/"):
            return {"jobs": [{"name": k, "conclusion": v} for k, v in self.jobs.items()]}
        if path.startswith("git/commits/"):
            return {"tree": {"sha": self.tree}, "parents": self.parents}
        if path.startswith("contents/"):
            return {"sha": self.workflow_blob}
        self.fail(path)

    def find(self, tree=None, platform=None):
        with patch.dict(os.environ, GITHUB_RUN_ID="999"), patch("ci_mini_reuse.git", return_value="expected"):
            return source_run([tree or self.tree], platform or self.platform, self.lookup)

    def test_same_tested_tree_across_commits(self):
        self.assertEqual(self.find(), (321, self.tree))
        self.assertIsNone(self.find(tree=self.head))
        self.assertIsNone(self.find(platform="2" * 64))
        self.parents.reverse()
        self.assertIsNone(self.find())

    def test_light_gate_fork_or_different_workflow_cannot_supply_evidence(self):
        self.jobs["swift"] = "skipped"
        self.assertIsNone(self.find())
        self.jobs["swift"] = "success"
        self.workflow_blob = "different"
        self.assertIsNone(self.find())
        self.workflow_blob = "expected"
        self.run["head_repository"]["full_name"] = "another/repo"
        self.assertIsNone(self.find())

    def test_gate_requires_successful_mini_plan_even_on_full_run(self):
        jobs = dict.fromkeys(("route","mini-plan","ifchange"), {"result":"success"})
        jobs.update(dict.fromkeys(("swift","app","release","nightly-data"), {"result":"skipped"}))
        self.assertTrue(passed(jobs, mini=True, reuse=True))
        self.assertFalse(passed(jobs, mini=True))
        self.assertFalse(passed(jobs, reuse=True))
        jobs["mini-plan"] = {"result":"failure"}
        self.assertFalse(passed(jobs, mini=True, reuse=True))


class ReleaseInputs(unittest.TestCase):
    def test_release_metadata_preserves_other_settings_and_every_previous_note(self):
        def files(rev, path):
            if path == "App/project.yml":
                version, build = ("1.0.0", "1") if rev == "old" else ("1.0.1", "2")
                return (f'  MARKETING_VERSION: "{version}"\n  CURRENT_PROJECT_VERSION: "{build}"\n' * 2)
            if path == "App/Info.plist":
                return "<key>DuoReleaseChannel</key><string>stable</string>"
            if path == "appcast.xml":
                return "<rss/>"
            history = "# Notes\n\n## 1.0.0\n\nOld note\n"
            return history if rev == "old" else history.replace("## 1.0.0", "## 1.0.1\n\nNew note\n\n## 1.0.0")

        with patch("ci_release_inputs.blob", side_effect=files):
            self.assertTrue(validate_metadata("old", "new"))
        for path in ("App/project.yml", "changelog/de.md"):
            def changed(rev, name):
                text = files(rev, name)
                return text + "changed" if (rev, name) == ("new", path) else text
            with self.subTest(path=path), patch("ci_release_inputs.blob", side_effect=changed):
                if path == "App/project.yml":
                    self.assertFalse(validate_metadata("old", "new"))
                else:
                    with self.assertRaises(ValueError):
                        validate_metadata("old", "new")

    def test_force_full_bypasses_lookup_and_historical_release_validation(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, GITHUB_SHA="sha",
                MINI_PLATFORM="platform", FORCE_FULL="true", GITHUB_OUTPUT=tmp + "/out"), \
                patch("ci_mini_reuse.git", side_effect=["sha", "tree"]), \
                patch("ci_mini_reuse.candidate_trees") as trees:
            main()
            trees.assert_not_called()
            self.assertIn("reuse=false", Path(tmp, "out").read_text())

    def test_new_feed_must_match_platform_even_when_it_has_the_right_version(self):
        ns = 'xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"'
        def feed(build):
            return (f"<rss {ns}><channel><item><sparkle:version>{build}</sparkle:version>"
                    "<sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>"
                    "<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>"
                    "<sparkle:hardwareRequirements>x86_64</sparkle:hardwareRequirements></item></channel></rss>")
        def files(rev, path):
            if path == "appcast.xml":
                return feed("1" if rev == "old" else "2")
            if path == "App/Info.plist":
                return "<plist><dict><key>DuoReleaseChannel</key><string>stable</string></dict></plist>"
            return '    macOS: "15.0"\n  ARCHS: arm64\n'
        with patch("ci_release_inputs.blob", side_effect=files), \
                patch("ci_release_inputs.project", return_value=("1.0.1", "2", "")):
            with self.assertRaisesRegex(ValueError, "system requirements"):
                validate_feed("old", "new")
            self.assertFalse(validate_feed("new", "new"))  # An existing-build reissue needs full CI.


if __name__ == "__main__":
    unittest.main()

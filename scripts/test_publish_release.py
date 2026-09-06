#!/usr/bin/env python3
"""Regression tests for the Sparkle-tooling lookup in `publish-release.sh`.

The functions under test are extracted from the real script and run with
`xcodegen` / `xcodebuild` stubbed out, so nothing here builds, resolves or
touches the network. Run by `make test`.

    python3 scripts/test_publish_release.py

Why a test at all for four lines of shell: 0.3.86 failed at exactly this point
(#371) and the failure message named the wrong cause, so the printed remedy did
nothing. Both halves — that the dependency now gets resolved, and that the
message stops blaming SKIP_NOTARIZE — are pinned below.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "publish-release.sh"


def extract_functions():
    """The two functions, verbatim, from the real script.

    Taken out rather than sourced: sourcing runs the whole script, which starts
    by talking to `gh`. Slicing by name and by the closing brace at column 0
    means a rename or a reshuffle fails here loudly instead of quietly testing
    a copy that has drifted from what ships.
    """
    lines = SCRIPT.read_text().splitlines()
    try:
        start = lines.index("find_generate_appcast() {")
        second = lines.index("ensure_generate_appcast() {")
    except ValueError as exc:  # pragma: no cover - structural
        raise AssertionError(f"{SCRIPT.name} no longer defines these: {exc}")
    end = next(i for i in range(second, len(lines)) if lines[i] == "}")
    return "\n".join(lines[start:end + 1])


FUNCTIONS = extract_functions()

DRIVER = """
set -euo pipefail
say() {{ printf 'SAY %s\\n' "$*" >&2; }}
die() {{ printf 'DIE %s\\n' "$*" >&2; exit 3; }}
REPO_ROOT="{repo_root}"
DERIVED_DATA="{derived_data}"
{functions}
ensure_generate_appcast
printf 'FOUND %s\\n' "$GENERATE_APPCAST"
"""

ARTIFACT = "SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"


class SparkleToolLookup(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="duo-371-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.dd = self.tmp / "dd"
        self.repo = self.tmp / "repo"
        (self.repo / "App").mkdir(parents=True)
        # Where the Sparkle dependency is pinned, and so the mtime the freshness
        # check compares against. Real, not absent: `[ missing -nt x ]` is false,
        # which would make "an artifact already on disk is used" pass for the
        # wrong reason and stop measuring the check at all.
        self.spec = self.repo / "App" / "project.yml"
        self.spec.write_text("name: DuoUpdater\n")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.log = self.tmp / "calls.log"

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def stub_xcodegen(self):
        # Records the team id it was generated with, which is the whole reason
        # the export exists: an empty DEVELOPMENT_TEAM does not fail here, it
        # fails the next `make install`.
        self.stub("xcodegen",
                  f'printf "xcodegen team=[$DUO_TEAM_ID]\\n" >> "{self.log}"')

    def stub_xcodebuild(self, *, creates):
        make = (f'mkdir -p "$(dirname "{self.dd}/{ARTIFACT}")" && '
                f'touch "{self.dd}/{ARTIFACT}" && chmod +x "{self.dd}/{ARTIFACT}"'
                ) if creates else "true"
        self.stub("xcodebuild",
                  f'printf "xcodebuild %s\\n" "$*" >> "{self.log}"\n' + make)

    def place_artifact(self, *, executable=True, stale=False):
        path = self.dd / ARTIFACT
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\ntrue\n")
        path.chmod(0o755 if executable else 0o644)
        # Whole seconds apart in both directions: `-nt` compares modification
        # times, and two files written in the same test can otherwise land in the
        # same tick and make the answer a coin flip.
        spec_mtime = os.stat(self.spec).st_mtime
        os.utime(path, (spec_mtime - 10, spec_mtime - 10) if stale
                 else (spec_mtime + 10, spec_mtime + 10))
        return path

    def run_driver(self):
        script = DRIVER.format(repo_root=self.repo, derived_data=self.dd,
                               functions=FUNCTIONS)
        env = dict(os.environ)
        # PATH is ours plus the system dirs `find`/`mkdir` live in — so an
        # absent stub means "this tool is not installed", which one case needs.
        env["PATH"] = f"{self.bin}:/usr/bin:/bin"
        env.pop("DUO_TEAM_ID", None)
        return subprocess.run(["bash", "-c", script], env=env,
                              capture_output=True, text=True)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ""

    # Mutation: drop the early `return 0` and it resolves every time.
    def test_an_artifact_newer_than_the_spec_is_used_as_is(self):
        self.place_artifact()
        self.stub_xcodegen()
        self.stub_xcodebuild(creates=False)
        run = self.run_driver()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn(f"FOUND {self.dd}/{ARTIFACT}", run.stdout)
        self.assertEqual(self.calls(), "", "resolved despite already having it")

    # A tool from an older Sparkle is not a tool. This directory outlives
    # dependency bumps, and on the CI_RUN_ID path nothing else resolves — so
    # "present" had to stop meaning "current".
    #
    # Mutation: delete the `-nt` line and this fails; nothing else does.
    def test_an_artifact_older_than_the_spec_is_re_resolved(self):
        self.place_artifact(stale=True)
        self.stub_xcodegen()
        self.stub_xcodebuild(creates=True)
        run = self.run_driver()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("-resolvePackageDependencies", self.calls())

    # Mutation: delete the resolve block (the state before #371) and this fails
    # — which is exactly how 0.3.86 failed.
    def test_a_missing_artifact_is_resolved_rather_than_refused(self):
        self.stub_xcodegen()
        self.stub_xcodebuild(creates=True)
        run = self.run_driver()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn(f"FOUND {self.dd}/{ARTIFACT}", run.stdout)
        self.assertIn("-resolvePackageDependencies", self.calls())
        self.assertIn(f"-derivedDataPath {self.dd}", self.calls())

    # Mutation: delete `export DUO_TEAM_ID=...` and the stub records an empty
    # team — the trap CLAUDE.md documents, silent until the next build.
    def test_the_project_is_generated_with_a_team_id(self):
        self.stub_xcodegen()
        self.stub_xcodebuild(creates=True)
        run = self.run_driver()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("xcodegen team=[", self.calls())
        self.assertNotIn("xcodegen team=[]", self.calls())

    # Mutation: `[ -x ]` -> `[ -e ]` and this passes a file that cannot be run.
    def test_a_non_executable_candidate_does_not_count_as_the_tool(self):
        self.place_artifact(executable=False)
        self.stub_xcodegen()
        self.stub_xcodebuild(creates=True)
        run = self.run_driver()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("-resolvePackageDependencies", self.calls())

    # Mutation: restore the old message and this fails. The old one named
    # SKIP_NOTARIZE, which the path that hit it does not even read.
    def test_the_refusal_names_the_resolve_not_skip_notarize(self):
        self.stub_xcodegen()
        self.stub_xcodebuild(creates=False)
        run = self.run_driver()
        self.assertEqual(run.returncode, 3, run.stdout)
        self.assertIn("resolving package dependencies", run.stderr)
        self.assertNotIn("SKIP_NOTARIZE", run.stderr)

    # Mutation: drop the `command -v xcodegen` check and the failure becomes
    # xcodegen's own "not found", from inside a subshell, with no remedy.
    def test_a_missing_xcodegen_is_named(self):
        self.stub_xcodebuild(creates=True)  # no xcodegen stub
        run = self.run_driver()
        self.assertEqual(run.returncode, 3, run.stdout)
        self.assertIn("xcodegen not found", run.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Regression tests for `check_ifchange`. Run by `make test`.

    python3 scripts/test_check_ifchange.py

The diff cases run the real `main` against a throwaway git repository, so they
exercise the same `git diff` parsing CI does. Each case names the rule it pins;
the ones that must NOT fire are paired with one that must, so a rule that
stopped firing at all cannot pass both.
"""

import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_ifchange as ci  # noqa: E402

SWIFT = """\
import Foundation

// LINT.IfChange(rule)
func rule(_ x: Int) -> Bool {
    x > 1
}
// LINT.ThenChange(witness.py:rule)

func unrelated() {}
"""

PY = """\
import sys

# LINT.IfChange(rule)
def rule(x):
    return x > 1
# LINT.ThenChange(core.swift:rule)

def unrelated():
    pass
"""


def errors_of(text, path="f.swift"):
    return ci.parse(path, text)[1]


class Markers(unittest.TestCase):

    def test_well_formed_pair_parses(self):
        blocks, errors = ci.parse("core.swift", SWIFT)
        self.assertEqual(errors, [])
        self.assertEqual([(b.label, b.start, b.end, b.targets) for b in blocks],
                         [("rule", 3, 7, [("witness.py", "rule")])])

    def test_unclosed_block(self):
        self.assertIn("never closed", errors_of("// LINT.IfChange(a)\nx\n")[0])

    def test_nested_block(self):
        text = "// LINT.IfChange(a)\n// LINT.IfChange(b)\n// LINT.ThenChange(x)\n"
        self.assertIn("do not nest", errors_of(text)[0])

    def test_then_change_without_if_change(self):
        self.assertIn("no LINT.IfChange open", errors_of("# LINT.ThenChange(x)\n")[0])

    def test_then_change_without_target(self):
        text = "// LINT.IfChange\n// LINT.ThenChange()\n"
        self.assertIn("names no target", errors_of(text)[0])

    def test_duplicate_label(self):
        text = ("// LINT.IfChange(a)\n// LINT.ThenChange(x)\n"
                "// LINT.IfChange(a)\n// LINT.ThenChange(y)\n")
        self.assertIn("already used", errors_of(text)[0])

    def test_marker_must_open_the_comment(self):
        """Prose and string literals that mention the marker are not markers."""
        text = ('let s = "// LINT.IfChange(a)"\n'
                "// See LINT.IfChange in the docs.\n"
                "`// LINT.ThenChange(x)`\n"
                "# LINT.IfChange / LINT.ThenChange links (see the script)\n")
        self.assertEqual(ci.parse("f.swift", text), ([], []))

    def test_comment_styles(self):
        for open_, close in (("// LINT.IfChange", "// LINT.ThenChange(x)"),
                             ("/// LINT.IfChange", "/// LINT.ThenChange(x)"),
                             ("# LINT.IfChange", "# LINT.ThenChange(x)"),
                             ("<!-- LINT.IfChange -->", "<!-- LINT.ThenChange(x) -->"),
                             (" * LINT.IfChange", " * LINT.ThenChange(x)")):
            with self.subTest(open_):
                blocks, errors = ci.parse("f", f"{open_}\nbody\n{close}\n")
                self.assertEqual((len(blocks), errors), (1, []))

    def test_several_targets_and_google_style_path(self):
        blocks, _ = ci.parse("f", "# LINT.IfChange\n# LINT.ThenChange(//a.py:x, b.md)\n")
        self.assertEqual(blocks[0].targets, [("a.py", "x"), ("b.md", None)])


class Repo(unittest.TestCase):
    """A git repository with `core.swift` and `witness.py` linked both ways."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.dir.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.write("core.swift", SWIFT)
        self.write("witness.py", PY)
        self.commit("base")
        self.git("checkout", "-q", "-b", "topic")
        self.env = mock_env(GITHUB_EVENT_PATH=None)
        self.env.__enter__()

    def tearDown(self):
        self.env.__exit__(None, None, None)
        self.dir.cleanup()

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def write(self, rel, text):
        (self.root / rel).write_text(text)

    def edit(self, rel, old, new):
        path = self.root / rel
        text = path.read_text()
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1))

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def run_check(self, *argv):
        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            rc = ci.main(list(argv), root=self.root)
        return rc, err.getvalue()


@contextlib.contextmanager
def mock_env(**values):
    saved = {k: os.environ.get(k) for k in values}
    for k, v in values.items():
        os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)
    try:
        yield
    finally:
        for k, v in saved.items():
            os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)


class Targets(Repo):

    def test_linked_tree_is_clean(self):
        self.assertEqual(self.run_check(), (0, ""))

    def test_missing_target_file(self):
        self.git("rm", "-q", "witness.py")
        rc, err = self.run_check()
        self.assertEqual(rc, 1)
        self.assertIn("witness.py is not a tracked file", err)

    def test_untracked_target_file_is_missing(self):
        """A file only in one person's working tree is not the other side."""
        self.write("extra.md", "notes\n")
        self.edit("witness.py", "core.swift:rule)", "core.swift:rule, extra.md)")
        rc, err = self.run_check()
        self.assertIn("extra.md is not a tracked file", err)

    def test_missing_target_label(self):
        """A rename on the other side leaves a link that guards nothing."""
        self.edit("witness.py", "IfChange(rule)", "IfChange(renamed)")
        rc, err = self.run_check()
        self.assertEqual(rc, 1)
        self.assertIn("witness.py declares no LINT.IfChange(rule)", err)


class Diff(Repo):

    def test_one_side_changed_fails(self):
        self.edit("core.swift", "x > 1", "x >= 1")
        rc, err = self.run_check("--base", "main")
        self.assertEqual(rc, 1)
        self.assertIn("core.swift:rule changed, but not witness.py:rule", err)

    def test_both_sides_changed_passes(self):
        self.edit("core.swift", "x > 1", "x >= 1")
        self.edit("witness.py", "x > 1", "x >= 1")
        self.assertEqual(self.run_check("--base", "main")[0], 0)

    def test_uncommitted_change_is_seen(self):
        """The working tree is the new side, so the check works before a commit."""
        self.edit("core.swift", "x > 1", "x >= 1")
        self.assertEqual(self.run_check("--base", "main")[0], 1)
        self.commit("one side")
        self.assertEqual(self.run_check("--base", "main")[0], 1)

    def test_target_changed_outside_its_block_does_not_count(self):
        self.edit("core.swift", "x > 1", "x >= 1")
        self.edit("witness.py", "    pass", "    return None")
        rc, err = self.run_check("--base", "main")
        self.assertEqual(rc, 1)
        self.assertIn("not witness.py:rule", err)

    def test_bare_path_target_accepts_any_change_in_the_file(self):
        self.write("doc.md", "# Doc\n\nThe rule is x > 1.\n")
        self.edit("core.swift", "witness.py:rule)", "witness.py:rule, doc.md)")
        self.commit("link doc")
        self.edit("core.swift", "x > 1", "x >= 1")
        self.edit("witness.py", "x > 1", "x >= 1")
        rc, err = self.run_check("--base", "HEAD")
        self.assertIn("not doc.md", err)
        self.edit("doc.md", "x > 1", "x >= 1")
        self.assertEqual(self.run_check("--base", "HEAD")[0], 0)

    def test_change_outside_any_block_is_free(self):
        self.edit("core.swift", "func unrelated() {}", "func unrelated() { }")
        self.assertEqual(self.run_check("--base", "main")[0], 0)

    def test_pure_deletion_inside_the_block_fails(self):
        self.edit("core.swift", "    x > 1\n", "")
        self.assertEqual(self.run_check("--base", "main")[0], 1)

    def test_pure_deletion_just_below_the_block_is_free(self):
        """Pairs with the case above: a cut right after `ThenChange` is outside."""
        self.edit("core.swift", "\nfunc unrelated() {}\n", "func unrelated() {}\n")
        self.assertEqual(self.run_check("--base", "main")[0], 0)

    def test_editing_only_the_markers_is_free(self):
        """Adding a target to a link is not a change to what the link guards."""
        self.write("doc.md", "x\n")
        self.git("add", "doc.md")
        self.edit("core.swift", "witness.py:rule)", "witness.py:rule, doc.md)")
        self.assertEqual(self.run_check("--base", "main")[0], 0)

    def test_introducing_a_link_is_free(self):
        """Both sides gain markers in one change: neither body 'changed'."""
        self.write("a.swift", "func f() {}\n")
        self.write("b.py", "def f(): pass\n")
        self.commit("unlinked")
        self.write("a.swift", "// LINT.IfChange(f)\nfunc f() {}\n// LINT.ThenChange(b.py:f)\n")
        self.write("b.py", "# LINT.IfChange(f)\ndef f(): pass\n# LINT.ThenChange(a.swift:f)\n")
        self.assertEqual(self.run_check("--base", "HEAD")[0], 0)

    def test_new_block_does_not_demand_its_targets_change(self):
        """New code written with a link to code that already exists: nothing the
        link guarded has changed yet, so the old side owes nothing."""
        self.edit("core.swift", "func unrelated() {}\n",
                  "func unrelated() {}\n\n// LINT.IfChange(more)\nfunc more() {}\n"
                  "// LINT.ThenChange(witness.py:rule)\n")
        self.assertEqual(self.run_check("--base", "main")[0], 0)

    def test_target_marker_edit_alone_does_not_count(self):
        """Renaming the other side's label touches its marker, not its body."""
        self.edit("core.swift", "x > 1", "x >= 1")
        self.edit("core.swift", "witness.py:rule)", "witness.py:rule2)")
        self.edit("witness.py", "IfChange(rule)", "IfChange(rule2)")
        rc, err = self.run_check("--base", "main")
        self.assertEqual(rc, 1)
        self.assertIn("not witness.py:rule2", err)

    def test_merge_base_not_tip_of_base(self):
        """`main` moving on after the branch point must not read as this branch's
        change. One-sided on purpose: a diff against main's tip sees core.swift
        alone and fails, so only the merge base passes."""
        self.git("checkout", "-q", "main")
        self.edit("core.swift", "x > 1", "x > 2")
        self.commit("main moves\n\nNO_IFTTT=fixture")
        self.git("checkout", "-q", "topic")
        self.assertEqual(self.run_check("--base", "main")[0], 0)


class Override(Repo):

    def test_commit_message_override_passes_with_warning(self):
        self.edit("core.swift", "x > 1", "x  > 1")
        self.commit("Reformat\n\nNO_IFTTT=whitespace only")
        rc, err = self.run_check("--base", "main")
        self.assertEqual(rc, 0)
        self.assertIn("⚠ core.swift:3", err)

    def test_override_needs_a_reason(self):
        self.edit("core.swift", "x > 1", "x  > 1")
        self.commit("Reformat\n\nNO_IFTTT=")
        self.assertEqual(self.run_check("--base", "main")[0], 1)

    def test_empty_override_does_not_borrow_the_next_line(self):
        """`NO_IFTTT=` followed by this repository's standard trailer, then an
        older commit and a PR description: none of those is the reason."""
        self.edit("core.swift", "x > 1", "x  > 1")
        self.commit("Older commit")
        self.edit("core.swift", "x  > 1", "x   > 1")
        self.commit("Reformat\n\nNO_IFTTT=\n\nCo-Authored-By: Someone <a@b.c>")
        event = self.root / "event.json"
        event.write_text(json.dumps({"pull_request": {"body": "Some description"}}))
        with mock_env(GITHUB_EVENT_PATH=str(event)):
            self.assertEqual(self.run_check("--base", "main")[0], 1)

    def test_pull_request_description_override(self):
        self.edit("core.swift", "x > 1", "x  > 1")
        self.commit("Reformat")
        event = self.root / "event.json"
        event.write_text(json.dumps({"pull_request": {"body": "NO_IFTTT=whitespace"}}))
        with mock_env(GITHUB_EVENT_PATH=str(event)):
            self.assertEqual(self.run_check("--base", "main")[0], 0)
        self.assertEqual(self.run_check("--base", "main")[0], 1)

    def test_override_on_main_does_not_leak_into_the_branch(self):
        self.git("checkout", "-q", "main")
        self.write("other.txt", "x\n")
        self.commit("old\n\nNO_IFTTT=something else")
        self.git("checkout", "-q", "topic")
        self.git("merge", "-q", "main")
        self.edit("core.swift", "x > 1", "x >= 1")
        self.assertEqual(self.run_check("--base", "main")[0], 1)


class RealTree(unittest.TestCase):

    def test_repository_markers_are_valid(self):
        _, errors = ci.scan()
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()

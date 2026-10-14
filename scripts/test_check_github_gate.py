#!/usr/bin/env python3
"""Tests for check_github_gate.py: each rule fires on the shape it exists for,
and stays quiet on the shapes the codebase uses. Run by `make test`."""

from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_github_gate as gate  # noqa: E402

KINDS = """
extension CLIToolKind {
    public var updaterSpendsGitHubAPI: UpdaterGitHubAPI? {
        switch self {
        case .uv, .bun, .mise: return .ourTokenIfAny
        case .zoxide, .atuin, .codex: return .anonymous
        default: return nil
        }
    }
}
"""


class Repo:
    """A scratch tree with the entry points and the kind list in place."""

    def __init__(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.dir.name)
        self.write("App/Sources/AppListModel.swift", "init() {\n    GitHubRateLimitGate.activate()\n}\n")
        self.write("CLI/Sources/duo/main.swift", "GitHubRateLimitGate.activate()\n")
        self.write(gate.KIND_LIST, KINDS)
        self.write(gate.TOKEN_SOURCE, "enum CLIToolGitHubToken {}\n")

    def write(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def problems(self) -> list[str]:
        return gate.check(self.root)


class CheckGitHubGateTests(unittest.TestCase):
    def test_a_clean_tree_passes(self) -> None:
        repo = Repo()
        repo.write("DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/Fine.swift",
                   'let url = URL(string: "https://api.github.com/repos/o/r")!\n'
                   "let (data, _) = try await session.countedData(for: request, purpose: .versionCheck)\n")
        self.assertEqual(repo.problems(), [])

    def test_a_raw_request_beside_the_api_fails_even_split_across_lines(self) -> None:
        repo = Repo()
        repo.write("DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/Bad.swift",
                   'let url = URL(string: "https://api.github.com/repos/o/r")!\n'
                   "let (data, _) = try await session.data(\n    for: request)\n")
        problems = repo.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn("Bad.swift:2", problems[0])

    def test_a_url_is_not_a_comment(self) -> None:
        """`//` in "https://" once hid every API URL from rule 1."""
        self.assertEqual(gate.strip_comment('let u = "https://api.github.com/x" // why'),
                         'let u = "https://api.github.com/x" ')

    def test_comments_do_not_count(self) -> None:
        repo = Repo()
        repo.write("DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/Doc.swift",
                   "/// Unlike `session.data(for:)`, this asks api.github.com through countedData.\n"
                   "let x = 1 // api.github.com\n")
        self.assertEqual(repo.problems(), [])

    def test_a_raw_request_without_the_api_is_not_this_checks(self) -> None:
        repo = Repo()
        repo.write("DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/Other.swift",
                   'let url = URL(string: "https://example.com/feed")!\n'
                   "let (data, _) = try await session.data(for: request)\n")
        self.assertEqual(repo.problems(), [])

    def test_the_allowed_file_may(self) -> None:
        repo = Repo()
        allowed = next(iter(gate.ALLOWED))
        repo.write(allowed, 'let url = URL(string: "https://api.github.com/rate_limit")!\n'
                            "let (data, _) = try await session.data(for: request)\n")
        self.assertEqual(repo.problems(), [])

    def test_an_entry_point_without_activate_fails(self) -> None:
        repo = Repo()
        repo.write("CLI/Sources/duo/main.swift", "// GitHubRateLimitGate.activate()\nrun()\n")
        problems = repo.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn("duo does not call", problems[0])

    def test_a_token_handed_to_an_unlisted_updater_fails(self) -> None:
        repo = Repo()
        repo.write("DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/UvUpdater.swift",
                   "let token = await CLIToolGitHubToken.app()\n")
        repo.write("DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/DenoUpdater.swift",
                   "let token = await CLIToolGitHubToken.app()\n")
        problems = repo.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn("DenoUpdater.swift", problems[0])
        self.assertIn("`deno`", problems[0])

    def test_the_real_tree_passes(self) -> None:
        repo = pathlib.Path(__file__).resolve().parent.parent
        self.assertEqual(gate.check(repo), [])


if __name__ == "__main__":
    unittest.main()

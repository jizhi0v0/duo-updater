#!/usr/bin/env python3
"""Refuse a request to the GitHub API that would go round the rate-limit gate.

Run by `make test`.

    python3 scripts/check_github_gate.py

## What this is for

`GitHubRateLimitGate` (DuoUpdaterCore/Traffic) is what stops DuoUpdater from
asking GitHub's REST API while GitHub has said the budget is spent. GitHub's
documentation: "Continuing to make requests while you are rate limited may
result in the banning of your integration." On 2026-10-14 the app's own request
log showed 381 refused requests in half an hour: every five-minute tick asked
again for every GitHub-tracked app and tool. The gate sits in
`URLSession.countedData` / `countedBytes`, so a request is covered only if it
goes through them, and only in a process that turned the gate on. A request
that goes round them, a new entry point that forgets `activate()`, or a new
vendor updater handed our token without the gate knowing, would put that back
without anything failing. This check makes each of those fail the build.

## The rules

1. A Swift file that names `api.github.com` must not send a request itself:
   no `.data(for:` / `.data(from:` / `.bytes(…` / `.upload(…` / `.download(…`
   / `dataTask(` outside a comment. It builds the request and hands it to
   `countedData` or `countedBytes`. The exceptions are `ALLOWED`, each with its
   reason.
2. Every process that sends real requests turns the gate on: the app
   (`AppListModel.init`) and `duo` (`main.swift`) call
   `GitHubRateLimitGate.activate()`.
3. A vendor update command handed our token (`CLIToolGitHubToken.app`) asks
   GitHub from its own process, past the gate; the gate holds its one-click
   back only for the kinds `CLIToolKind.updaterSpendsGitHubAPI` lists. Every
   `*Updater.swift` that hands the token over must be one of those kinds.

## What it cannot see

Rule 1 looks at one file at a time. A helper elsewhere that sends whatever URL
it is given — an API URL built in another file — is not caught. Every such
helper today is `countedData`, `countedBytes` or `versionFeedData` (which calls
`countedData`); a new one must be too.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOTS = ("DuoUpdaterCore/Sources", "App/Sources", "CLI/Sources")

# Files that may name the API and send a request themselves, with why.
ALLOWED = {
    "DuoUpdaterCore/Sources/DuoUpdaterCore/Traffic/GitHubAnonymousBudget.swift":
        "GET /rate_limit for Settings' display: free of the primary budget, and "
        "the gate exempts it by path",
}

RAW_REQUEST = re.compile(r"\.(?:data|bytes|upload|download)\(\s*(?:for|from):|\bdataTask\(")

ENTRY_POINTS = {
    "App/Sources/AppListModel.swift": "the app",
    "CLI/Sources/duo/main.swift": "duo",
}
ACTIVATE = re.compile(r"^\s*GitHubRateLimitGate\.activate\(\)", re.MULTILINE)

KIND_LIST = "DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/CLITool.swift"
TOKEN_SOURCE = "DuoUpdaterCore/Sources/DuoUpdaterCore/CLITools/CLIToolGitHubToken.swift"


def strip_comment(line: str) -> str:
    """`line` without its `//` comment. A `//` inside a string literal — every
    `"https://…"` — is not one: cutting there hid every API URL from rule 1."""
    in_string = False
    index = 0
    while index < len(line):
        char = line[index]
        if char == "\\" and in_string:
            index += 2
            continue
        if char == '"':
            in_string = not in_string
        elif not in_string and line.startswith("//", index):
            return line[:index]
        index += 1
    return line


def code_lines(text: str) -> list[tuple[int, str]]:
    """Each line with its number, with `//` comments (and `///`) removed."""
    return [(number, strip_comment(line)) for number, line in enumerate(text.split("\n"), start=1)]


def code_only(text: str) -> str:
    return "\n".join(line for _, line in code_lines(text))


def raw_requests(text: str) -> list[int]:
    """Line numbers of requests sent directly, comments ignored."""
    code = code_only(text)
    return [code.count("\n", 0, match.start()) + 1 for match in RAW_REQUEST.finditer(code)]


def token_kinds(kind_list: str) -> set[str]:
    """The kinds `updaterSpendsGitHubAPI` says take our token."""
    match = re.search(r"case\s+([.\w,\s]+?):\s*return\s+\.ourTokenIfAny", kind_list)
    if not match:
        return set()
    return {name.strip().lstrip(".").lower() for name in match.group(1).split(",") if name.strip()}


def check(repo: pathlib.Path) -> list[str]:
    problems: list[str] = []

    for root in ROOTS:
        for path in sorted((repo / root).rglob("*.swift")):
            relative = path.relative_to(repo).as_posix()
            text = path.read_text(encoding="utf-8")
            if "api.github.com" not in code_only(text) or relative in ALLOWED:
                continue
            for line in raw_requests(text):
                problems.append(
                    f"{relative}:{line}: names api.github.com and sends a request itself — "
                    "hand it to countedData/countedBytes so the rate-limit gate sees it")

    for relative, who in ENTRY_POINTS.items():
        path = repo / relative
        if not path.exists() or not ACTIVATE.search(code_only(path.read_text(encoding="utf-8"))):
            problems.append(f"{relative}: {who} does not call GitHubRateLimitGate.activate()")

    kinds = token_kinds(code_only((repo / KIND_LIST).read_text(encoding="utf-8")))
    for root in ROOTS:
        for path in sorted((repo / root).rglob("*Updater.swift")):
            relative = path.relative_to(repo).as_posix()
            if relative == TOKEN_SOURCE or "CLIToolGitHubToken" not in code_only(path.read_text(encoding="utf-8")):
                continue
            kind = path.stem[: -len("Updater")].lower()
            if kind not in kinds:
                problems.append(
                    f"{relative}: hands our GitHub token to a vendor command, but `{kind}` is not "
                    "in CLIToolKind.updaterSpendsGitHubAPI's .ourTokenIfAny — the gate would not "
                    "hold its one-click back while the budget is closed")
    return problems


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parent.parent
    problems = check(repo)
    for problem in problems:
        print(f"✗ {problem}")
    if problems:
        return 1
    print("✓ GitHub API requests all pass the rate-limit gate")
    return 0


if __name__ == "__main__":
    sys.exit(main())

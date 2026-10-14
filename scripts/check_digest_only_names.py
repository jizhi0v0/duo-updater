#!/usr/bin/env python3
"""The Settings text that names the digest-only apps must name exactly those apps.

Run by `make test`.

    python3 scripts/check_digest_only_names.py

The toggle "Allow one-click updates for apps without a developer signature"
(App/Sources/Settings/GeneralSettingsPage.swift) lists by name the apps whose
GitHub rule installs through `.publishedDigestOnly`. A user decides whether to
turn it on from that list. Onboarding a digest-only app without adding its name
leaves the list false, and nothing else notices: the text is not in the
onboarding's diff, and on 2026-10-14 the Claude review, replayed at high and at
xhigh on the Lokii and disktree onboardings, missed it both times
(bench/onboarding/results/review-replay.yml).

A recipe is matched to a listed name by its GitHub repository name, ignoring
case. When an app's name differs from its repository's, add it to ALIASES.
Every translation in Localizable.xcstrings must carry the same names.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RECIPES = ROOT / "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes"
SETTINGS = ROOT / "App/Sources/Settings/GeneralSettingsPage.swift"
XCSTRINGS = ROOT / "App/Resources/Localizable.xcstrings"
MARKER = "only ad-hoc signed"
# repository name (lowercase) -> the name the Settings text uses
ALIASES: dict[str, str] = {}


def strip_comments(swift: str) -> str:
    """Drop `//` comments, leaving string literals (which may contain `//`) alone."""
    out = []
    for line in swift.splitlines():
        in_str = False
        cut = len(line)
        i = 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            elif not in_str and line.startswith("//", i):
                cut = i
                break
            i += 1
        out.append(line[:cut])
    return "\n".join(out)


def digest_only_repos(sources: dict[str, str]) -> dict[str, str]:
    """Repository name (lowercase) -> recipe file, for every rule installing digest-only."""
    found = {}
    for name, text in sources.items():
        code = strip_comments(text)
        for m in re.finditer(r"\.publishedDigestOnly\b", code):
            repos = re.findall(r'\brepo:\s*"([^"]+)"', code[:m.start()])
            if not repos:
                raise SystemExit(f"{name}: `.publishedDigestOnly` with no `repo:` before it")
            found[repos[-1].lower()] = name
    return found


def listed_names(swift: str) -> tuple[str, list[str]]:
    """The literal that carries MARKER, and the names it lists between dashes."""
    for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', swift):
        if MARKER in literal:
            m = re.search(MARKER + r" — (.+?) —", literal)
            if not m:
                raise SystemExit(f"{SETTINGS.relative_to(ROOT)}: can't find the ' — names — ' list in: {literal}")
            return literal, [n.strip() for n in re.split(r",| and ", m.group(1)) if n.strip()]
    raise SystemExit(f"{SETTINGS.relative_to(ROOT)}: no string literal contains {MARKER!r}")


def problems(repos: dict[str, str], literal: str, names: list[str], xcstrings: dict) -> list[str]:
    out = []
    wanted = {ALIASES.get(r, r): f for r, f in repos.items()}
    have = {n.lower(): n for n in names}
    for want, recipe in sorted(wanted.items()):
        if want.lower() not in have:
            out.append(f"{recipe} installs digest-only, but the Settings text doesn't name it "
                       f"({SETTINGS.relative_to(ROOT)}: {', '.join(names)}). Add its name, "
                       f"or map its repository name in ALIASES.")
    for low, shown in sorted(have.items()):
        if low not in {w.lower() for w in wanted}:
            out.append(f"the Settings text names {shown!r}, but no recipe installs it digest-only")
    entry = xcstrings.get("strings", {}).get(literal)
    if entry is None:
        out.append(f"{XCSTRINGS.relative_to(ROOT)} has no entry keyed by the Settings text")
    else:
        for lang, loc in sorted(entry.get("localizations", {}).items()):
            value = loc.get("stringUnit", {}).get("value", "")
            missing = [n for n in names if n not in value]
            if missing:
                out.append(f"{XCSTRINGS.relative_to(ROOT)} [{lang}] doesn't name {', '.join(missing)}")
    return out


def main() -> int:
    sources = {p.name: p.read_text() for p in sorted(RECIPES.glob("*.swift"))}
    repos = digest_only_repos(sources)
    literal, names = listed_names(SETTINGS.read_text())
    found = problems(repos, literal, names, json.loads(XCSTRINGS.read_text()))
    for p in found:
        print("✗ " + p)
    if found:
        return 1
    print(f"✓ digest-only apps named in Settings: {', '.join(names)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Bump DuoUpdater's cask in its Homebrew tap to a just-published release.

    python3 scripts/homebrew_tap.py <version> <sha256> [--repo owner/homebrew-tap]

Called by publish-release.sh once the GitHub Release and the appcast are live,
and only for a release that publishes the appcast: never for a draft (its
assets 404 for everyone but the author) or a prerelease (the stable feed does
not offer it, so the cask must not either).
It clones the tap, rewrites `version` and `sha256` in Casks/duoupdater.rb, and
pushes the commit to the tap's main. The tap is jizhi0v0/homebrew-tap, which
installs with `brew install --cask jizhi0v0/tap/duoupdater`.

A lagging tap breaks no one. The cask is `auto_updates true`: `brew upgrade` leaves
the app alone, and an install from a stale cask is updated by Sparkle within the
hour. So the caller treats a failure here as a warning, and this script exits
non-zero only so that the caller can say so.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CASK_PATH = "Casks/duoupdater.rb"
VERSION_RE = re.compile(r'^(  version ")([^"]*)(")$', re.MULTILINE)
SHA_RE = re.compile(r'^(  sha256 ")([0-9a-f]{64})(")$', re.MULTILINE)


def bump(text: str, version: str, sha256: str) -> str:
    """Return the cask with `version` and `sha256` replaced.

    Exactly one of each must be present. The cask has a single artifact, and
    rewriting a guess is worse than refusing, so anything else raises.
    """
    if not re.fullmatch(r"\d+(\.\d+)+", version):
        raise ValueError(f"not a release version: {version!r}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError(f"not a sha256: {sha256!r}")
    for name, pattern in (("version", VERSION_RE), ("sha256", SHA_RE)):
        count = len(pattern.findall(text))
        if count != 1:
            raise ValueError(f"expected one {name} line in the cask, found {count}")
    text = VERSION_RE.sub(lambda m: f"{m.group(1)}{version}{m.group(3)}", text)
    return SHA_RE.sub(lambda m: f"{m.group(1)}{sha256}{m.group(3)}", text)


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          capture_output=True).stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("version")
    parser.add_argument("sha256")
    parser.add_argument("--repo", default="jizhi0v0/homebrew-tap")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="duo-homebrew-tap.") as tmp:
        clone = Path(tmp) / "tap"
        run("gh", "repo", "clone", args.repo, str(clone), "--", "--depth=1", "--quiet")
        cask = clone / CASK_PATH
        before = cask.read_text(encoding="utf-8")
        after = bump(before, args.version, args.sha256)
        if after == before:
            print(f"   tap      : {args.repo} already at {args.version}")
            return 0
        cask.write_text(after, encoding="utf-8")
        run("git", "add", CASK_PATH, cwd=clone)
        run("git", "commit", "--quiet", "-m", f"duoupdater {args.version}", cwd=clone)
        run("git", "push", "--quiet", "origin", "HEAD", cwd=clone)
    print(f"   tap      : {args.repo} bumped to {args.version}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, ValueError, OSError) as error:
        detail = getattr(error, "stderr", "") or ""
        print(f"homebrew tap bump failed: {error} {detail}".strip(), file=sys.stderr)
        sys.exit(1)

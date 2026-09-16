#!/usr/bin/env python3
"""Does duoupdater.app state the same minimum macOS as the release just published?

    scripts/site_floor.py <site-checkout> <LSMinimumSystemVersion of the shipped app>

Called at the end of `publish-release.sh`, beside the changelog-sync reminder, and
for the same reason: the site is a separate repository, nothing about publishing
touches it, and its "macOS 14 or later" is hand-written in three places. Raising
the deployment target changes what the app needs the moment the release is out,
and nothing else would say that the download page now promises a Mac on the old
floor something it cannot run.

It only prints. A site that is behind is not a reason to stop a release that has
already been published, and the sync that fixes it is a manual step anyway.

The release's floor is read from the shipped app (`LSMinimumSystemVersion`), not
from `App/project.yml`: the bundle is what users get. The site is read from its
`origin/main` after a fetch, because that is what is deployed; a local checkout
can be days behind. What counts as a statement is the phrasing the site uses —
"macOS N or later" and "macOS N+" — and the site's copy of the changelog is left
out, since release notes talk about other apps' requirements.

Exit status: 0 the site agrees, 1 it states a different floor, 2 could not tell
(no floor in the app, no statement found on the site, git failed). Only 0 prints
the green line: finding nothing is not agreement.
"""

import re
import subprocess
import sys

# Group 1 is the major version. `N.M or later` counts as N: the site speaks in
# majors, and a floor of 15.0 or 15.4 is still "macOS 15" to a reader. A phrasing
# with a name in between ("macOS 15 Sequoia or later") is NOT matched — the site
# does not use one today, and a pattern loose enough to allow it would also match
# "macOS 26 apps, or later".
STATED = re.compile(r"macOS[  ]+(\d+)(?:\.\d+)*[  ]*(?:\+|or later|or newer)")

# Paths inside the site repository that are not the site describing itself.
EXCLUDED = ("content/changelog.md",)


def major(version):
    """"15.0" -> "15". None when there is no leading number to read."""
    match = re.match(r"\s*(\d+)", version or "")
    return match.group(1) if match else None


def stated_floors(lines):
    """`(path, line number, major, text)` for every statement of a minimum macOS
    in `(path, line number, text)` lines, skipping `EXCLUDED`."""
    out = []
    for path, number, text in lines:
        if path in EXCLUDED:
            continue
        for match in STATED.finditer(text):
            out.append((path, number, match.group(1), text.strip()))
    return out


def verdict(release_minimum, stated):
    """(status, message lines) for the release floor against the site statements."""
    want = major(release_minimum)
    if want is None:
        return 2, [f"the shipped app declares no readable LSMinimumSystemVersion ({release_minimum!r})"]
    if not stated:
        return 2, ["found no \"macOS N or later\" / \"macOS N+\" on the site — "
                   "it may have been reworded, so this check no longer sees it"]
    wrong = [s for s in stated if s[2] != want]
    if not wrong:
        return 0, [f"states macOS {want}+ in {len(stated)} place(s), matching this release"]
    return 1, [f"{path}:{number}  says macOS {said}:  {text}" for path, number, said, text in wrong]


def site_lines(site_repo):
    """Lines mentioning macOS on the deployed branch, as `(path, number, text)`.

    Returns `(ref, lines)`; raises `RuntimeError` when git cannot answer.
    """
    fetched = subprocess.run(["git", "-C", site_repo, "fetch", "--quiet", "origin"],
                             capture_output=True, text=True, timeout=60)
    ref = "origin/main"
    if fetched.returncode != 0 or subprocess.run(
            ["git", "-C", site_repo, "rev-parse", "--verify", "--quiet", ref],
            capture_output=True).returncode != 0:
        raise RuntimeError(f"could not fetch {ref} in {site_repo}: {fetched.stderr.strip()}")
    grep = subprocess.run(["git", "-C", site_repo, "grep", "-n", "-I", "-e", "macOS", ref, "--"],
                          capture_output=True, text=True)
    if grep.returncode not in (0, 1):  # 1 is "no match", which is an answer
        raise RuntimeError(f"git grep failed in {site_repo}: {grep.stderr.strip()}")
    lines = []
    for row in grep.stdout.splitlines():
        # `origin/main:path:line:text` — the ref itself contains no colon.
        _, path, number, text = row.split(":", 3)
        lines.append((path, int(number), text))
    return ref, lines


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    site_repo, release_minimum = argv[1], argv[2]
    try:
        ref, lines = site_lines(site_repo)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        status, message = 2, [str(error)]
        ref = "origin/main"
    else:
        status, message = verdict(release_minimum, stated_floors(lines))

    if status == 0:
        print(f"\033[1;32m   site     : duoupdater.app {message[0]}\033[0m")
    elif status == 1:
        print(f"\n\033[1;33m! duoupdater.app states a different minimum macOS than this release.\033[0m")
        print(f"  This release requires macOS {release_minimum} (the shipped app). On {ref}:")
        for line in message:
            print(f"    {line}")
        print("\n  Change those lines in the site repository together with the changelog sync.")
    else:
        print(f"\n\033[1;33m! Could not compare duoupdater.app with this release's minimum macOS.\033[0m")
        for line in message:
            print(f"  {line}")
        print("  Check the download page by hand: it should state what the shipped app needs.")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))

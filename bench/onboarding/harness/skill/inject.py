"""inject.py <clone> — run-one-b.sh with SKILL=1: insert the coverage checklist into the clone's app-audit
skill, just above the not-yet-integrated workflow, and commit it. Drops the
digest-only sentence where the clone has no `.publishedDigestOnly` (it predates
#952), so the treatment never names an API the clone lacks."""
import pathlib, subprocess, sys
clone = pathlib.Path(sys.argv[1])
text = (pathlib.Path(__file__).parent / "coverage-checklist.md").read_text()
src = subprocess.run(["git", "grep", "-l", "publishedDigestOnly", "--", "DuoUpdaterCore/Sources"],
                     cwd=clone, capture_output=True, text=True).stdout
if not src.strip():
    drop = ("  Ad-hoc signing alone doesn't make an app detection-only: `installTrust:\n"
            "  .publishedDigestOnly` covers it when the conditions on `InstallTrust` hold.\n")
    assert text.count(drop) == 1, "digest-only sentence not found exactly once"
    text = text.replace(drop, "")
skill = clone / ".claude/skills/app-audit/SKILL.md"
body = skill.read_text()
anchor = "## § Not yet integrated — investigation workflow\n"
assert body.count(anchor) == 1, "anchor not found exactly once"
i = body.index(anchor) + len(anchor)
# after the heading's first paragraph
j = body.index("\n\n", i) + 2
skill.write_text(body[:j] + text + body[j:])
subprocess.run(["git", "commit", "-qam", "app-audit: coverage checklist"], cwd=clone, check=True)
print(subprocess.run(["git", "rev-parse", "HEAD"], cwd=clone, capture_output=True, text=True).stdout.strip())

#!/bin/bash
# Cherry-pick agent commits onto the current branch, resolving ONLY the two
# conflicts every recipe batch produces: one-line rows in
# docs/app-audits/README.md and `<family>.set,` rows in AppRecipeIndex.swift.
# Any other conflict stops the run and leaves the cherry-pick for a human.
#
#   .claude/skills/coverage-discovery/scripts/integrate.sh <sha> [<sha> ...]
set -u
INDEX=DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/AppRecipeIndex.swift
README=docs/app-audits/README.md

union() {  # $1 = file, $2 = regex every conflicting line must match
  python3 - "$1" "$2" <<'PY'
import re, sys
path, line_re = sys.argv[1], re.compile(sys.argv[2])
s = open(path).read()
def merge(m):
    lines = (m.group(1) + m.group(2)).splitlines(keepends=True)
    for ln in lines:
        if not line_re.fullmatch(ln.rstrip("\n")):
            sys.exit(f"{path}: refusing to auto-merge {ln!r}")
    if path.endswith(".swift"):  # the index is sorted by family slug, case-insensitively
        return "".join(sorted(set(lines), key=lambda l: l.strip().lower()))
    return "".join(lines)
out, n = re.subn(r"^<<<<<<< [^\n]*\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n", merge, s, flags=re.S | re.M)
if "<<<<<<<" in out or ">>>>>>>" in out:
    sys.exit(f"{path}: conflict markers left")
open(path, "w").write(out)
print(f"  {path}: {n} block(s) merged")
PY
}

for c in "$@"; do
  if ! git cherry-pick "$c" >/dev/null 2>&1; then
    for f in $(git diff --name-only --diff-filter=U); do
      case "$f" in
        "$README") union "$f" '- \[x\] \[.*' || exit 1;;
        "$INDEX")  union "$f" '\s+\w+\.set,' || exit 1;;
        *) echo "conflict in $f while picking $c — resolve by hand, then git cherry-pick --continue"; exit 1;;
      esac
      git add "$f"
    done
    GIT_EDITOR=true git cherry-pick --continue >/dev/null || { echo "cherry-pick --continue failed on $c"; exit 1; }
  fi
  echo "picked $c → $(git log -1 --format='%h %s')"
done

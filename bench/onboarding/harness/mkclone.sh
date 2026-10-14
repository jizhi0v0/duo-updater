#!/bin/bash
# mkclone.sh <dest> <commit> — a clone whose history ENDS at <commit>: no later
# objects, no remote, so the agent cannot read the merged answer from git.
set -euo pipefail
dest=$1; commit=$2
. "$(dirname "$0")/env.sh"; SRC=$DUO_REPO
mkdir -p "$dest"; cd "$dest"
git init -q -b main
git fetch -q --depth 300 "file://$SRC" "$commit"
git checkout -q -B main FETCH_HEAD
git config user.name jizhi0v0; git config user.email 57976101+jizhi0v0@users.noreply.github.com
# remove any object not reachable from HEAD
git reflog expire --expire=now --all; git gc -q --prune=now
echo "clone at $(git rev-parse --short HEAD), $(git rev-list --count HEAD) commits"

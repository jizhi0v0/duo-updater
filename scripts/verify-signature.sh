#!/usr/bin/env bash
#
# Refuse to ship a binary whose signature cannot hold a TCC grant.
#
# macOS keys grants (App Management, Full Disk Access, Accessibility, Automation)
# to a code identity. An ad-hoc signature pins the grant to the CDHash, so every
# rebuild invalidates it and the permission prompt comes back; an identity-based
# designated requirement (anchor apple generic + team OU) is identical across
# rebuilds, so a grant given once persists.
#
# Extracted from install.sh so `duo` is held to the same bar as the app rather
# than to a second copy of these three checks that can drift from it.
#
# Usage:  scripts/verify-signature.sh <path-to-app-or-binary> [team]
#
set -euo pipefail

TARGET="${1:?usage: verify-signature.sh <path> [team]}"
TEAM="${2:-RS59HDH7Y3}"

die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Capture codesign output into variables and grep those, rather than piping
# `codesign | grep -q`: under `set -o pipefail`, grep -q exits early on a match
# and codesign takes SIGPIPE mid-write, which pipefail then reports as a failed
# pipeline — a timing-dependent false negative.
sig="$(codesign -dvv "$TARGET" 2>&1)"
req="$(codesign -d -r- "$TARGET" 2>&1)"

case "$sig" in *"adhoc"*) die "$TARGET is AD-HOC signed — check CODE_SIGN_IDENTITY in App/project.yml";; esac
case "$sig" in *"TeamIdentifier=$TEAM"*) ;; *) die "$TARGET is not signed by team $TEAM";; esac
# The designated requirement must be identity-based (anchor apple generic + team
# OU), NOT a bare cdhash — that identity-form is what makes grants survive rebuilds.
case "$req" in *"anchor apple generic"*) ;; *) die "$TARGET's designated requirement is not identity-based (cdhash-pinned?) — grants won't persist";; esac

printf '%s\n' "$req" | sed -n 's/^designated => /   designated => /p'

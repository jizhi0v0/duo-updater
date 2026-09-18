#!/usr/bin/env bash
# Decides what the Claude review job does for this push and writes its prompt.
# See .github/workflows/claude-review.yml for the round model.
#
# Inputs (env): REPO PR HEAD_SHA BASE_REF PR_AUTHOR WORK
#   PR_TITLE PR_BODY  from the event payload; written to a file for the reviewer
#   COMMENTS_JSON  optional: read PR comments from this file instead of the API
#                  (used to test this script locally)
#   GH_TOKEN  required unless COMMENTS_JSON is set; the workflow sets it on this
#             step alone, so a new `gh` call here needs it passed, not assumed
# Outputs ($GITHUB_OUTPUT): mode=full|recheck|skip, round, prompt
set -euo pipefail

: "${REPO:?}" "${PR:?}" "${HEAD_SHA:?}" "${BASE_REF:?}" "${PR_AUTHOR:?}" "${WORK:?}"
: "${GITHUB_OUTPUT:?}"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK"

# The title and description go to a file the reviewer reads, never into the
# prompt: the prompt travels through a heredoc in $GITHUB_OUTPUT, and free
# text could contain its delimiter.
printf '# %s\n\n%s\n' "${PR_TITLE:-}" "${PR_BODY:-(no description)}" > "$WORK/pr.md"

if [ -n "${COMMENTS_JSON:-}" ]; then
  cp "$COMMENTS_JSON" "$WORK/comments.json"
else
  gh api --paginate "repos/$REPO/issues/$PR/comments" | jq -s 'add // []' > "$WORK/comments.json"
fi

# The newest comment this workflow posted. Only github-actions[bot] can author
# it, and the marker is read from the end of the body, so text quoted inside a
# review cannot stand in for it.
last="$(jq -c '
  [ .[] | select(.user.login == "github-actions[bot]")
        | . as $c
        | ([ .body | match("<!-- claude-review:v1 sha=([0-9a-f]{40}) round=([0-9]+) -->"; "g") ] | last) as $m
        | select($m != null)
        | { created_at, body, sha: $m.captures[0].string, round: ($m.captures[1].string | tonumber) } ]
  | last // empty' "$WORK/comments.json")"

emit() { # mode round
  echo "mode=$1" >> "$GITHUB_OUTPUT"
  echo "round=$2" >> "$GITHUB_OUTPUT"
  echo "mode=$1 round=$2"
}

fill() { # template -> prompt output
  local t
  t="$(cat "$1")"
  t="${t//@PR@/$PR}"
  t="${t//@HEAD_SHA@/$HEAD_SHA}"
  t="${t//@MERGE_BASE@/${merge_base:-}}"
  t="${t//@PREV_SHA@/${prev_sha:-}}"
  t="${t//@PREV@/$WORK/prev-round.md}"
  t="${t//@OUT@/$WORK/review.md}"
  t="${t//@PRINFO@/$WORK/pr.md}"
  printf '%s\n' "$t" > "$WORK/prompt.md"
  {
    echo "prompt<<CLAUDE_REVIEW_PROMPT_EOF"
    cat "$WORK/prompt.md"
    echo "CLAUDE_REVIEW_PROMPT_EOF"
  } >> "$GITHUB_OUTPUT"
}

full_review() { # round
  git fetch --quiet origin "$BASE_REF"
  merge_base="$(git merge-base "origin/$BASE_REF" "$HEAD_SHA")"
  emit full "$1"
  fill "$here/full.md"
}

if [ -z "$last" ]; then
  full_review 1
  exit 0
fi

prev_sha="$(jq -r .sha <<<"$last")"
prev_round="$(jq -r .round <<<"$last")"
next_round=$((prev_round + 1))

if [ "$prev_sha" = "$HEAD_SHA" ]; then
  emit skip "$prev_round"
  exit 0
fi

# History rewritten since the last review (force-push, rebase): the recorded
# SHA no longer describes an ancestor, so there is no increment to recheck.
if ! git cat-file -e "$prev_sha^{commit}" 2>/dev/null || ! git merge-base --is-ancestor "$prev_sha" "$HEAD_SHA"; then
  echo "Reviewed SHA $prev_sha is not an ancestor of $HEAD_SHA; reviewing in full."
  full_review "$next_round"
  exit 0
fi

if [ -z "$(git rev-list --first-parent --no-merges "$prev_sha..$HEAD_SHA")" ]; then
  echo "Only merge commits since $prev_sha; nothing to recheck."
  emit skip "$prev_round"
  exit 0
fi

# Previous review, then the author's comments posted after it (their verdicts).
jq -r --arg author "$PR_AUTHOR" --argjson last "$last" '
  "## Previous review (round \($last.round), \($last.sha[0:7]))\n\n\($last.body)\n",
  ( [ .[] | select(.user.login == $author and .created_at > $last.created_at) ]
    | if length == 0 then "## Author comments since then\n\n(none)"
      else "## Author comments since then\n", (.[] | "---\n\(.created_at)\n\n\(.body)\n") end )
' "$WORK/comments.json" > "$WORK/prev-round.md"

emit recheck "$next_round"
fill "$here/recheck.md"

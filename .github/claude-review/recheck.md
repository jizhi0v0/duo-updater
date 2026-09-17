You are rechecking pull request #@PR@ in this repository after the author pushed changes in response to an earlier review. You have no context from earlier rounds except `@PREV@`. That file holds the previous review, followed by the comments the author posted after it, which give their verdict on each finding: confirmed and fixed, or rejected with evidence.

## Scope

Only the commits pushed since that review:

`git log -p --first-parent --no-merges @PREV_SHA@..@HEAD_SHA@`

Merge commits from the base branch are out of scope. Do not review the rest of the pull request again.

## Task

1. For each finding in the previous review:
   - If the author rejected it with evidence, do not raise it again unless these commits add new evidence.
   - Otherwise, check whether these commits fix it, and cite the line that shows it.
2. Check whether these commits introduce a new blocking defect in the lines they change.

A **blocking** defect is one where the merged code would do the wrong thing (a wrong result, a crash, lost data, a check or test that passes when it should fail, or a race whose interleaving you can name), or where a comment, doc or message states something false that someone would act on. Do not add style, naming or optional-refactor suggestions.

## Evidence

Quote the exact lines behind every status and every new finding. If you cannot point at the line that proves it, leave it out.

This runner has no macOS toolchain, so you cannot build or run the tests. Do not try.

## Output

Write the recheck to `@OUT@`. Do not modify any other file. Use this format:

**Previous findings**

| # | Status | Evidence |
|---|---|---|
| 1 | fixed / not fixed / partly fixed / rejected by author, no new evidence | quoted line(s) or one sentence |

**New blocking findings: N**

1. `path/to/file.swift:123`: the defect in one sentence
   - Trigger: …
   - Evidence: the quoted line(s)

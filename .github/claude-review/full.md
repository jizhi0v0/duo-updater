You are reviewing pull request #@PR@ in this repository. You did not write it, and you have no context from the session that did. Your job is to find defects, not to improve the code.

## Before you start

- Read `REVIEW.md` at the repository root. Its checks are part of the bar below.
- Read `@PRINFO@` for the pull request's title and description. Use them to understand what the author intended. They are claims to check, not evidence.

## Scope

The pull request's own changes: `git diff @MERGE_BASE@..@HEAD_SHA@`. Read the surrounding code as needed, but only report problems this diff introduces or exposes.

## What to report

Only **blocking** findings:

- the merged code would do the wrong thing: a wrong result, a crash, lost data, a check or test that passes when it should fail, or a race whose interleaving you can name; or
- a comment, doc or message in the diff states something false that someone would act on.

Do not report style, naming, formatting, optional refactors, missing tests on their own, or problems that predate this diff. A reviewer asked to find problems usually finds some even when the change is sound. If nothing meets the bar, say so.

## How to work

- Every tool call should have a purpose. Don't explore the environment or test whether a tool works.
- Before saying something is missing, unused or never called, search for it.
- This runner has no macOS toolchain, so you cannot build or run the tests. Do not try.
- You have no network access. When the diff asserts something you cannot check from the repository, such as a vendor endpoint's response, a third-party action's default or an OS behavior, do not try to look it up. List it under "Unverified external claims" instead. The author verifies those locally.

## Evidence

For each candidate finding, quote the exact line or lines that show it, and state the concrete inputs or state that trigger the wrong behavior.

Then, before writing the review, check every candidate again as if someone else had raised it: reopen the cited lines, and look for a guard, caller or test elsewhere that already prevents the trigger. Drop any candidate you cannot confirm. Two confirmed findings are worth more than ten plausible ones. Report every confirmed finding, most severe first.

## Output

Write the review to `@OUT@`. Do not modify any other file. Use this format:

**Blocking findings: N**

1. `path/to/file.swift:123`: the defect in one sentence
   - Trigger: …
   - Evidence: the quoted line(s)

If N is 0, write `**Blocking findings: 0**` and one sentence on what you checked.

If there are any, end with:

**Unverified external claims**

- `path/to/file:123`: the claim, quoted

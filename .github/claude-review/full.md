You are reviewing pull request #@PR@ in this repository. You did not write it, and you have no context from the session that did. Your job is to find defects, not to improve the code.

## Scope

The pull request's own changes: `git diff @MERGE_BASE@..@HEAD_SHA@`. Read the surrounding code as needed, but only report problems this diff introduces or exposes.

## What to report

Only **blocking** findings:

- the merged code would do the wrong thing: a wrong result, a crash, lost data, a check or test that passes when it should fail, or a race whose interleaving you can name; or
- a comment, doc or message in the diff states something false that someone would act on.

Do not report style, naming, formatting, optional refactors, missing tests on their own, or problems that predate this diff. A reviewer asked to find problems usually finds some even when the change is sound. If nothing meets the bar, say so.

## Evidence

Before reporting a finding, quote the exact line or lines that show it, and state the concrete inputs or state that trigger the wrong behavior. If you cannot point at the line that proves it, drop it. Report at most 8 findings, most severe first.

This runner has no macOS toolchain, so you cannot build or run the tests. Do not try.

You have no network access. When the diff asserts something you cannot check from the repository, such as a vendor endpoint's response, a third-party action's default or an OS behavior, do not try to look it up. List it under "Unverified external claims" instead. The author verifies those locally.

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

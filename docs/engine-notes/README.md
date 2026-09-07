# Engine Notes

Maintenance docs for "trim the core-path comments" work (issue #409). The
comment next to the code should carry only the **current contract / non-obvious
constraint / boundary / pointer to the test or design doc that backs it**.
Everything else — incident timelines, full measurements, arguments against a
rejected design — belongs here instead. One file per source file it explains,
named for the source file in kebab-case: `AppStorePageCache.swift` →
`app-store-page-cache.md`.

## What this directory is not

`/docs/*` is gitignored by default (see the repo's `.gitignore`) because most
of what lands under `docs/` is machine-specific inventory — which apps are
installed, which channel each one runs. `docs/engine-notes/` is carved out the
same way `docs/app-audits/` and `docs/update-manifest-families.md` are, and the
carve-out comes with the same condition: **no installed-app inventory lives
here either.** A dated measurement is fine to write down, but say plainly that
it is a one-time measurement, not a tracked metric — see the "measured
2026-09-05" note in `app-store-page-cache.md` §4.2 for the format, including
what to do when the number has already drifted once.

## Checklist for migrating a comment here

1. **Classify every comment block**: (a) current contract / non-obvious
   constraint / boundary → stays in the code, kept short; (b) incident
   timeline, full measurement, discussion of a rejected design → moves here;
   (c) no longer true → verify and rewrite, or delete and say why in the PR —
   never copy it across unchanged.
2. **Re-check every historical claim before moving it**, especially: the
   default check interval, TTL values, and anything that counts "N of this
   machine's X" — that shape is the one `scripts/check_prose_claims.py`
   exists to keep out of code comments (see its docstring), and moving it into
   a doc doesn't make an unverifiable count trustworthy, it just makes the
   "unverifiable" part honest. What can't be re-verified in this pass gets
   labeled "unverified, as written in the original" or "quoted from the prior
   comment, not re-measured" — never folded into the same sentence as a
   claim that was checked.
3. **Leave a way back in the code**: one line, this doc's path, and the
   section heading, so the next reader can find the full story instead of
   being told it doesn't matter.
4. **`grep` for other copies of the sentence you're about to move** — test
   files' own "why this test exists" comments, `.claude/skills/`, `.agents/`,
   READMEs. A test's own incident retelling does not have to be kept in sync
   (it is documenting the test, not the class), but say in the PR how many
   copies you found and why the ones you left alone were left alone.
5. **Run `scripts/check_prose_claims.py`** (wired into `make test`). It only
   catches one shape of stale claim (a machine-population count); passing it
   is not proof the rest of the comment is still accurate.
6. `make test`, then a self-review pass (`/code-review`) on the diff before
   opening the PR.

## Index

- [`app-store-page-cache.md`](app-store-page-cache.md) — `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/AppStorePageCache.swift`

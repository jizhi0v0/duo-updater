#!/usr/bin/env python3
"""Brute-force the interleavings that `app_test_coverage`'s console parser sees.

WHY THIS EXISTS, AND WHY IT IS COMMITTED
========================================
`scripts/app_test_coverage.py` reads swift-testing's console records out of a
log that several writers append to concurrently, so a record and a stderr log
line can be glued together mid-line. The parser defends against that, and the
comments in it quote numbers from a sweep run on 2026-09-17 "with a script that
is not committed, so the numbers can't be re-run from this repo".

That bit us. CI run 35492361595 (2026-09-20) failed the gate with
`theClientRequirementIsPinnedForATeam` reported as never run, on a commit that
touches nothing under `App/`; the next run on the same branch passed, and six
local runs were 51-of-51. To tell "a tear shape we already know we miss" from
"the parser regressed" there has to be a runnable enumeration. This is it.

WHAT IT ENUMERATES
==================
Each writer (a swift-testing record, one or two stderr log lines) is torn into
pieces at every position, and the pieces are interleaved every way that keeps
each writer's own pieces in order — which is exactly what concurrent
`write(2)`s to one fd can produce. Two questions are asked of every text:

  RECALL  — the record is a genuine PASS record. Does the parser still find the
            name? A miss here is a FALSE RED: the 2026-09-20 failure's shape.
            Misses are expected and are inventoried, not asserted away.

  SAFETY  — the record did NOT pass (started / failed / skipped), and the log
            text ends in something like `passed`. Does the parser report the
            name as having run? A hit here is a FALSE GREEN: the gate would
            stop catching a skipped case, which is the whole reason it exists.
            Any hit is a hard failure of this sweep.

The asymmetry is deliberate. A false red costs a rerun; a false green costs the
guarantee. So the parser is tuned to keep SAFETY at zero and accept RECALL
misses, and this script's job is to keep the exact inventory of those misses
honest rather than re-derived from memory.

USAGE
=====
    python3 scripts/sweep_app_test_coverage.py            # the standard sweep
    python3 scripts/sweep_app_test_coverage.py --quick    # used by the unit tests
    python3 scripts/sweep_app_test_coverage.py --verbose  # print example missed texts

Measured 2026-09-20 on an M-series Mac: the standard sweep reports 2196554
texts across its SAFETY and RECALL sections in 10.5s; the quick mode reports
268100 in 4.2s. (The by-shape table re-walks the 895200 two-by-two recall
texts to attribute them, so it is not added in.) The quick mode trims the
record and log corpora, never the enumeration, so every interleaving ORDERING
is still visited and a SAFETY regression cannot hide behind it.

Exits non-zero if any SAFETY hit is found; if the RECALL miss inventory has
changed shape in EITHER direction (an ordering that was fully recovered started
missing, or a known-missing one stopped missing — both make the numbers quoted
in `app_test_coverage.py` and `test_app_test_coverage.py` wrong); or if any
section visited no texts at all, which would make the whole sweep vacuous.
"""

import argparse
import itertools
import pathlib
import sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import app_test_coverage as atc  # noqa: E402

NAME = "foo"

# Records, copied in shape from real logs. `✔`/`━` are the pass markers; `◇`,
# `✘` and `➜` are start / fail / skip, which must never be counted.
PASS_RECORDS = [
    "✔ Test foo() passed after 0.004 seconds.\n",
    "✔ Test foo(_:) with 2 test cases passed after 0.002 seconds.\n",
    "━ Test foo() passed after 0.001 seconds with 1 known issue.\n",
    "\U0010105B  Test foo() passed after 0.013 seconds.\n",
]
NONPASS_RECORDS = [
    "◇ Test foo() started.\n",
    "✘ Test foo() failed after 0.001 seconds with 1 issue.\n",
    "➜ Test foo() skipped.\n",
    "◇ Test foo(_:) started.\n",
    "\U00100884  Test foo() failed after 0.001 seconds with 1 issue.\n",
]

# Real stderr lines from the App-test logs, plus adversarial ones whose message
# ends in the exact text the parser looks for. The last group is the #716
# counterexample family: text that, spliced into a torn record, could hand it a
# verdict it never earned.
TS = "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] "
LOG_LINES = [
    TS + "duo-helper: rejected connection — no client requirement is installed\n",
    "2026-09-13 19:21:20.342690+0800 xctest[16059:13752262] [logging-persist] cannot open file\n",
    TS + "helper: probe (ok) passed\n",
    TS + "check(x) passed\n",
    TS + ") passed\n",
    TS + "_:) passed\n",
    TS + ") with 2 test cases passed\n",
    TS + "a() passed\n",
    TS + "✔ Test \n",
    TS + "━ Test foo(\n",
]


def tears(s, pieces):
    """Every way of cutting `s` into exactly `pieces` non-empty runs, in order.

    A writer that is interrupted mid-`write` shows up in the log as its bytes
    split at one point; two interruptions split it at two. The cut points are
    the interleaving's degrees of freedom, so they are enumerated, not sampled.
    """
    n = len(s)
    if pieces == 1:
        return [(s,)]
    out = []
    for cuts in itertools.combinations(range(1, n), pieces - 1):
        bounds = (0,) + cuts + (n,)
        out.append(tuple(s[bounds[i]:bounds[i + 1]] for i in range(len(bounds) - 1)))
    return out


def interleavings(*streams):
    """Every merge of the streams that preserves each stream's internal order.

    Modelled as choosing, for each output slot, which stream the next piece
    comes from — i.e. the distinct permutations of a multiset of stream ids.
    """
    ids = []
    for i, s in enumerate(streams):
        ids.extend([i] * len(s))
    seen = set()
    for order in set(itertools.permutations(ids)):
        if order in seen:
            continue
        seen.add(order)
        cursors = [0] * len(streams)
        out = []
        for which in order:
            out.append(streams[which][cursors[which]])
            cursors[which] += 1
        yield "".join(out)


# The RECALL inventory, pinned so the docstring's promise is enforced rather
# than asserted. These are the interleaving ORDERINGS of a torn pass record and
# a torn log line, and they do not depend on --quick: `recall_by_shape` always
# walks the full record and log corpora.
#
# The two that miss are the ones where the log line's own newline arrives after
# a piece of the record, so cutting the line out takes record text with it.
# Recovering them means allowing text between `)` and `passed` that the log line
# could have written, which is how a torn non-passing record borrows a verdict —
# see `app_test_coverage.py`. They are expected to stay missing.
#
# Checked in BOTH directions on purpose. An ordering that starts missing is a
# regression that would otherwise ship as a mystery false red — the exact cost
# this script was committed to remove. An ordering that stops missing is good
# news, but it silently falsifies the recovery percentages quoted in
# `app_test_coverage.py` and in `test_app_test_coverage.py`'s `KnownConsoleMisses`,
# so it has to be a deliberate edit, not a drift.
EXPECTED_FULLY_RECOVERED = {
    "log1|log1|record|record",
    "log1|record|record|log1",
    "record|log1|log1|record",
    "record|record|log1|log1",
}
EXPECTED_WITH_MISSES = {
    "log1|record|log1|record",
    "record|log1|record|log1",
}


def inventory_problems(table, totals):
    """Compare a by-shape RECALL table against the pinned inventory.

    Split out of `main()` so the comparison can be tested on synthetic tables
    rather than only through a live sweep. Review of 9f54148f made the point:
    the sweep's success line is printed unconditionally, so a test that only
    asserts the line still passes if the comparison is deleted. A test that
    calls this directly does not.

    Returns (regressed, improved, unknown), each a sorted list of ordering
    labels; all three empty means the inventory is unchanged.
    """
    known = EXPECTED_FULLY_RECOVERED | EXPECTED_WITH_MISSES
    # Reported once each. An ordering the inventory does not name is `unknown`
    # and nothing else: without this it would ALSO land in `regressed` or
    # `improved`, and print advice about updating percentages that do not
    # mention it. (Found by the unit test below, not by reading.)
    unknown = set(totals) - known
    seen_with_misses = {label for label in totals if table[label]} - unknown
    seen_clean = {label for label in totals if not table[label]} - unknown
    return (
        # Was fully recovered, now misses: a new false-red shape.
        sorted(seen_with_misses - EXPECTED_WITH_MISSES),
        # Was known to miss, now clean: good, but it falsifies the quoted
        # percentages, so it has to be a deliberate edit.
        sorted(seen_clean - EXPECTED_FULLY_RECOVERED),
        sorted(unknown),
    )


def shape_of(order):
    """A readable label for an interleaving, e.g. `record|log|record|log`."""
    return "|".join("record" if i == 0 else f"log{i}" for i in order)


def sweep_two(records, log_lines, record_pieces, log_pieces, want, verbose, budget=None):
    """One record against one log line. Returns (total, hits, examples)."""
    total = 0
    hits = 0
    examples = []
    for rec in records:
        for log in log_lines:
            for rpieces in tears(rec, record_pieces):
                for lpieces in tears(log, log_pieces):
                    for text in interleavings(rpieces, lpieces):
                        total += 1
                        found = NAME in atc.ran_cases(text)
                        if found != want:
                            hits += 1
                            if verbose and len(examples) < 5:
                                examples.append(text)
                        if budget and total >= budget:
                            return total, hits, examples
    return total, hits, examples


def sweep_three(records, log_lines, want, verbose, budget):
    """A record, a log line, and a second, genuine pass record for ANOTHER case.

    This is the dangerous configuration: a real `✔` from an unrelated record is
    on hand for a torn non-pass record to borrow. Every writer is torn in two.
    """
    donor = "✔ Test bar() passed after 0.001 seconds.\n"
    total = 0
    hits = 0
    examples = []
    for rec in records:
        for log in log_lines:
            for rpieces in tears(rec, 2):
                for lpieces in tears(log, 2):
                    for dpieces in tears(donor, 2):
                        for text in interleavings(rpieces, lpieces, dpieces):
                            total += 1
                            found = NAME in atc.ran_cases(text)
                            if found != want:
                                hits += 1
                                if verbose and len(examples) < 5:
                                    examples.append(text)
                            if total >= budget:
                                return total, hits, examples
    return total, hits, examples


def recall_by_shape(verbose):
    """Which ORDERINGS of a torn pass record and a torn log line are recovered.

    The parser's own comments name three orderings it cannot recover. This
    reproduces that inventory by ordering, so a change that silently loses an
    ordering it used to handle shows up as a changed table rather than as a
    flaky CI run months later.
    """
    table = Counter()
    totals = Counter()
    for rec in PASS_RECORDS:
        for log in LOG_LINES:
            for rpieces in tears(rec, 2):
                for lpieces in tears(log, 2):
                    for order in sorted(set(itertools.permutations([0, 0, 1, 1]))):
                        cursors = [0, 0]
                        parts = []
                        for which in order:
                            parts.append((rpieces, lpieces)[which][cursors[which]])
                            cursors[which] += 1
                        text = "".join(parts)
                        label = shape_of(order)
                        totals[label] += 1
                        if NAME not in atc.ran_cases(text):
                            table[label] += 1
    return table, totals


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true",
                    help="tear each writer at a coarse subset of positions")
    ap.add_argument("--verbose", action="store_true", help="print example texts")
    # Test-only. `inventory_problems` is unit-tested directly, which pins the
    # comparison but NOT the fact that main() still acts on it — deleting the
    # regressed/improved/unknown block below would leave those tests green
    # (round 3 of review named this residual). This flag injects an inventory
    # change into an otherwise healthy run so a caller can assert that main()
    # reports it and exits non-zero. It only ever makes the sweep stricter.
    ap.add_argument("--selftest-inventory", action="store_true",
                    help="inject an inventory regression; the run must then fail")
    args = ap.parse_args()

    # The quick mode trims the corpus, not the enumeration: every ordering is
    # still visited, so a SAFETY regression cannot hide behind it.
    pass_recs = PASS_RECORDS[:1] if args.quick else PASS_RECORDS
    nonpass_recs = NONPASS_RECORDS[:2] if args.quick else NONPASS_RECORDS
    logs = LOG_LINES[:4] if args.quick else LOG_LINES
    three_budget = 20000 if args.quick else 500000

    failed = False
    # Every section's text count, checked at the end. A sweep whose enumeration
    # silently produced nothing would otherwise print `0 texts, 0 false passes
    # [ok]` for each section and exit 0 — a gate against vacuous test runs,
    # passing vacuously. This is the same failure `app-tests.sh` guards against
    # with its `DECLARED = 0` branch.
    visited: dict[str, int] = {}

    print("SAFETY — a non-pass record must never be counted, however it is torn")
    for rp, lp in ((1, 1), (2, 1), (1, 2), (2, 2)):
        total, hits, examples = sweep_two(nonpass_recs, logs, rp, lp, False, args.verbose)
        visited[f"safety r{rp}/l{lp}"] = total
        status = "ok" if hits == 0 else "FALSE GREEN"
        print(f"  record in {rp}, log in {lp}: {total:>8} texts, {hits} false passes  [{status}]")
        if hits:
            failed = True
            for e in examples:
                print(f"      {e!r}")

    total, hits, examples = sweep_three(nonpass_recs, logs, False, args.verbose, three_budget)
    visited["safety three-writer"] = total
    status = "ok" if hits == 0 else "FALSE GREEN"
    print(f"  + a donor pass record, all three torn: {total:>8} texts, {hits} false passes  [{status}]")
    if hits:
        failed = True
        for e in examples:
            print(f"      {e!r}")

    print()
    print("RECALL — a genuine pass record; misses are false reds, not unsoundness")
    for rp, lp in ((1, 1), (2, 1), (1, 2), (2, 2)):
        total, misses, examples = sweep_two(pass_recs, logs, rp, lp, True, args.verbose)
        visited[f"recall r{rp}/l{lp}"] = total
        pct = 100.0 * (total - misses) / total if total else 0.0
        print(f"  record in {rp}, log in {lp}: {total:>8} texts, {misses} missed  ({pct:.1f}% recovered)")
        for e in examples:
            print(f"      {e!r}")

    print()
    print("RECALL by interleaving order (both writers torn in two)")
    table, totals = recall_by_shape(args.verbose)
    if args.selftest_inventory:
        # Flip an ordering that must be fully recovered into a miss. This is
        # the exact shape of the 2026-09-20 false red, and the run must fail.
        table[sorted(EXPECTED_FULLY_RECOVERED)[0]] = 1
    for label in sorted(totals):
        miss = table[label]
        tot = totals[label]
        print(f"  {label:<32} {tot - miss:>6}/{tot:<6} recovered"
              + ("" if miss == 0 else f"   ({miss} missed)"))

    # The docstring promises this check; without it the table above is
    # decoration, and an ordering that regressed from fully-recovered to
    # missing would exit 0 with `make test` still green.
    regressed, improved, unknown = inventory_problems(table, totals)
    if regressed:
        failed = True
        print()
        print("✗ RECALL inventory changed: these orderings were fully recovered"
              " and now miss:")
        for label in regressed:
            print(f"    {label}  ({table[label]} of {totals[label]} missed)")
        print("  That is a new false-red shape. Do not widen the inventory to"
              " silence it.")
    if improved:
        failed = True
        print()
        print("✗ RECALL inventory changed: these orderings were expected to miss"
              " and no longer do:")
        for label in improved:
            print(f"    {label}")
        print("  Good news, but it falsifies the recovery figures quoted in"
              " app_test_coverage.py")
        print("  and in test_app_test_coverage.py's KnownConsoleMisses. Update"
              " both, then the")
        print("  inventory above — and say how a verdict still cannot be"
              " borrowed.")
    if unknown:
        failed = True
        print()
        print(f"✗ RECALL inventory does not name these orderings: {unknown}")

    visited["recall by-shape"] = sum(totals.values())
    empty = sorted(name for name, count in visited.items() if count == 0)
    if empty:
        failed = True
        print()
        print("✗ these sections visited NO texts, so they proved nothing:")
        for name in empty:
            print(f"    {name}")

    print()
    if failed:
        print("✗ sweep failed — see the sections above")
        return 1
    print("✓ sweep found no false green, and the RECALL inventory is unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main())

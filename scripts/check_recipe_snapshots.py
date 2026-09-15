#!/usr/bin/env python3
"""Refuse a dated measurement snapshot in a recipe family's comments.

Run by `make test`.

    python3 scripts/check_recipe_snapshots.py

## What this is for

Step 2 of the recipe refactor moved dated verification logs, incident timelines
and measured numbers out of `Recipes/<family>.swift` comments and into that
family's `docs/app-audits/<family>.md` under `## 历史与实测`, leaving the code
with the current contract and a `// History:` pointer (convention:
`docs/app-audits/README.md` §「从 recipe 注释迁出的历史」). Moving them once
does not stop the next recipe PR from writing the same kind of sentence
straight back: on the day batch 2d merged, three of six recipe PRs had done
exactly that (#610 "2026-09-14 it answered with the same `ccc-7.2.8399.zip`",
#622 "Verified against the live page 2026-09-14: 10 entries", #623 "on
2026-09-14 it said mac `1.0.910.1`" and "51 entries on 2026-09-14"). The skills
did not mention the convention at all.

## Which families

Every family is guarded: every `*.swift` file under `Recipes/` except the two
infrastructure files `AppRecipeIndexTests.infrastructure` also names, and every
`*.json5` file under `Resources/Recipes/` (a family written as data, whose
comments are whole `//` lines too). A brand new family is guarded from its first
commit. A missing directory fails the run, and the number of guarded families
must equal the number of recipe goldens, so a family the listing misses fails it
too (`recipe_families.py`).

## Shapes

Comment lines are joined per paragraph (a run of non-blank `//` lines) and split
into sentences, because the sentences wrap: Windscribe's "measured on the newest
40" ends one line and "releases (2026-09-07): 9 are stable" starts the next, and
a line scanner sees neither half. Indented lines are excerpts (README: 缩进的摘录)
and are data, not prose. A History pointer token is taken out of its line and
the rest of the line is scanned. A sentence is flagged when it matches one of `SHAPES`;
see the comment on each.

Allowed, because the migration batches and the convention keep them in code:

  * a provenance clause with no observed value — "(checked 2026-09-14)",
    "(measured 2026-08-27 across Intel/Sequoia/browser agents)",
    "(Ed25519, checked 2026-09-04)" (#621, decision 1);
  * a sentence that says where the measurement went — "History has …",
    "(…, History)";
  * "when checked (<date> …)" on a vendor-state sentence, even with a value.
    补充七条 rule 2 depends on it: deleting the date from such a sentence makes a
    timeless claim. It is also the easiest way to dodge this check — write any
    snapshot as "when checked" and it passes. Review covers that, not this script;
  * a sample quoted for its shape — "(captured verbatim 2026-08-16):" over an
    indented excerpt. The excerpt is not prose, so no value follows the date;
  * labels and vendor-event dates — "MARK: - 2026-09-12 …", "released 2024-11-12",
    "tags since 2026-09-12" — and present-tense replay dates ("on 2026-08-01 the
    three answer …"), which no shape matches.

`snapshot-lint:allow — <reason>` at the start of a comment line exempts every
hit in ITS paragraph (not the whole comment block, so a new snapshot a paragraph
further down still fails). The reason is mandatory. A marker whose paragraph no
longer has a hit fails the build: a dead exemption is a standing pass for
whatever is written there next (`check_prose_claims.py`, `mayLookAlike`, #271).

## What it does NOT do

It is a net, not a proof. Replayed against the four migration batches, it flags
85 of the 169 dated sentences those batches moved or rewrote (about 50%; the
denominator also holds rewrites that kept their date). Many misses are a
trailing "(measured <date>)" after a value, a shape the batches themselves
treated inconsistently and #621 decision 1 keeps. Two wider shapes (a value right
before "on <date>", a verb-date-value with no punctuation) caught 14 more of those
sentences, measured before `count-then-dated-paren` was added, and also flagged
Windscribe's test-replay dates, so they were left out.

Verified misses, each a sentence this script passes today:

  * a noun subject, or a verb outside `OBSERVED`: "A live fetch on <date> showed
    …", "Today (<date>) the feed holds …", "Mounted the … dmg <date>:",
    "Response on <date>: HTTP 200";
  * a version between the verb and the date ("Verified 1.2.3 on <date>: …"),
    because `measurement-led` does not cross a period;
  * indented prose and indented bullets, which are read as excerpts;
  * `date-led` only where a sentence starts, which in practice is the start of a
    paragraph: "… moved. <date>: …" is not split there;
  * "History has …" exempts the sentence it sits in, snapshot included;
  * dates that are not ISO (`Sep 14, 2026`), and trailing `// …` or `/* … */`
    comments, which are never read;
  * undated snapshots ("(38 entries)", "the newest 13 have none"): without a
    date there is no shape to tell a snapshot from a contract.

Rewording to dodge a shape also dodges the check; the point is to make the shape
unwelcome, and to name where it belongs, not to be unfoolable.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import recipe_families as families  # noqa: E402

# Which files are families is `recipe_families.py`'s answer. Families written as
# data (`RecipeFamilyFile`) have whole-line `//` comments only, so the paragraph
# reading below is the same for them.
RECIPES = families.RECIPES
RECIPE_DATA = families.RECIPE_DATA

DATE = r"20\d\d-\d\d-\d\d"
OBSERVED = (r"(?:measured|re-?measured|verified|re-?verified|observed|checked|"
            r"re-?checked|counted|confirmed|tested|probed|sampled|fetched)")
COUNTED = (r"(?:entries|entry|items|releases|versions|builds|tags|assets|results|"
           r"matches|headings|rows|pages|bytes|characters|files|links|candidates)")
PAST = (r"(?:said|answered|returned|served|listed|showed|gave|had|held|carried|"
        r"reported|named|pointed|resolved|redirected|responded|led|kept|contained|"
        r"was|were|matched|agreed|yielded|published|shipped|\w+ed)")

# What an observation says it saw. Two shapes below require one after the date,
# which is what separates "measured 2026-09-07: 9 are stable" from the allowed
# "(measured 2026-08-27 across Intel/Sequoia/browser agents)".
VALUE = re.compile(
    r"\b\d+(?:\.\d+){1,3}\b"                          # 1.0.910.1
    r"|`[^`]*(?:\d+\.\d+|\d{2,})[^`]*`"               # `ccc-7.2.8399.zip`
    r"|\b\d[\d,]*\s+(?:\w+\s+)?" + COUNTED + r"\b"    # 10 entries, 100 releases
    r"|\b\d+\s+`[^`]+`"                               # 33 `desktop-*`
    r"|\b(?:all\s+)?\d+\s+of\s+the\b"                 # all 19 of the
    r"|\b\d+\s+(?:are|were)\b"                        # 9 are stable
    r"|\b\d+/\d+\b"                                   # 98/100
    r"|\b(?:exactly|only)\s+(?:one|two|three|four|five|\d+)\b"
    r"|\b[1-5]\d\d\b(?=\s*(?:\"|\(|with|for|and|,|\.|$))", re.I)

# name -> (pattern, whether a VALUE must follow in the `rest` group)
SHAPES = {
    # README (b): "以实测为主语的句子（"Measured …"、"Verified …"）整句搬走". The
    # sentence opens, within three words, with the observation and its date.
    "measurement-led": (re.compile(
        rf"^\W*(?:[\w.-]+\s+){{0,3}}?{OBSERVED}\b[^.]{{0,80}}?\b{DATE}", re.I), False),
    # "on 2026-09-14 it said mac `1.0.910.1`" — a dated, past-tense report of what
    # an endpoint did. Present tense is left alone: Windscribe's "on 2026-08-01
    # the three answer 2.23.11" describes what the regression tests replay.
    "dated-narrative": (re.compile(
        rf"\b(?:on\s+)?{DATE},?\s+(?:it|they|both|all\s+\w+|the\s+\w+(?:\s+\w+)?|"
        rf"this|that|[\d.]+)\s+{PAST}\b(?P<rest>[^;]{{0,160}})", re.I), True),
    # "measured on the newest 40 releases (2026-09-07): 9 are stable"
    "observed-then-values": (re.compile(
        rf"\b{OBSERVED}\b[^.;:()]{{0,60}}?\(?\b{DATE}\)?[^.;:()]{{0,60}}?\s*[:,]\s*"
        rf"(?P<rest>[^;]{{0,160}})", re.I), True),
    # "2026-08-09: the bare `/changelog` root is NOT this app's changelog any more"
    "date-led": (re.compile(rf"^\W*{DATE}\s*:"), False),
    # "Shape (51 entries on 2026-09-14)"
    "count-on-date": (re.compile(
        rf"\b\d[\d,]*\s+(?:\w+\s+)?{COUNTED}\s+(?:on|as\s+of)\s+{DATE}", re.I), False),
    # "still shipping as of 2026-08-18"
    "as-of": (re.compile(rf"\bas\s+of\s+{DATE}", re.I), False),
    # "121 entries parse from the live page (2026-08-31), head 14.8" — a count,
    # then the day it was counted in parentheses, inside one clause.
    "count-then-dated-paren": (re.compile(
        rf"\b\d[\d,]*\s+(?:\w+\s+)?{COUNTED}\b[^.;:()]{{0,60}}?\(\s*{DATE}\s*\)",
        re.I), False),
}

# The sentence already names where the measurement lives.
HISTORY_REFERENCE = re.compile(
    r"\bHistory\s+(?:has|quotes|records|keeps|holds)\b|[(,]\s*History\)")
# The pointer itself, as `check_app_audits.py` reads it. Only the token (and a
# leading "History:") is taken out of the prose; the rest of that line is scanned.
HISTORY_POINTER = re.compile(r"docs/app-audits/[A-Za-z0-9._-]+\.md#历史与实测")
POINTER_TOKEN = re.compile(r"(?:\bHistory:\s*)?" + HISTORY_POINTER.pattern)
# 补充七条 rule 2. A known dodge; see the docstring.
WHEN_CHECKED = re.compile(
    rf"\bwhen\s+(?:checked|verified|measured)\b[^.;]{{0,40}}{DATE}", re.I)

MARKER = "snapshot-lint:allow"
# At least one word character: "— " and "— ." are not reasons.
REASON = re.compile(re.escape(MARKER) + r"\s*[—-]\s*(.*\w.*)")
ABBREVIATION = re.compile(r"\b(?:e\.g|i\.e|etc|vs|cf|approx|no)\.$", re.I)

# One sentence per shape that must be caught, and allowed sentences that must
# not be. Checked on every run, so a shape broken by an edit fails the build even
# if nobody touched the tests — the same reason `check_offpool.py` requires every
# BLOCKING spelling to match something.
CANARIES = {
    "measurement-led": "Verified against the live page 2026-09-14: 10 entries, "
                       "1.104.0 back to 1.95.0, all parsing.",
    "dated-narrative": "The platforms do not ship together: on 2026-09-14 it said "
                       "mac `1.0.910.1` and win `1.0.914.1`.",
    "observed-then-values": "WHAT THIS LISTS, measured on the newest 40 releases "
                            "(2026-09-07): 9 are stable and 31 are prereleases.",
    "date-led": "2026-08-09: the bare `/changelog` root is NOT this app's "
                "changelog any more.",
    "count-on-date": "Shape (51 entries on 2026-09-14): `## v1.0.914.1` headings.",
    "as-of": "The v1 train is still shipping as of 2026-08-18.",
    "count-then-dated-paren": "121 entries parse from the live page (2026-08-31), "
                              "head 14.8.",
}
ALLOWED_CANARIES = [
    "Both answer any client the same way (measured 2026-08-27 across "
    "Intel/Sequoia/ browser agents), which is precisely why.",
    "The key verifies that item's signature (Ed25519, checked 2026-09-04), but "
    "note what that is.",
    "Measured 2026-08-24 (History has the table), the consumer values (`free`, "
    "`go`) resolved to a newer build.",
    "It states a bare number (`\"latest_version\": 4200` when checked 2026-09-14).",
    "Each item (captured verbatim 2026-08-16):",
    "The regression tests use those dates: on 2026-08-01 the three answer "
    "2.23.11 / 2.23.11 / 2.24.6.",
    "A `-preview.` series has appeared (tags since 2026-09-12, releases since "
    "2026-09-13) and is not covered.",
]


def paragraphs(text):
    """[(line number, text)] per run of non-blank, non-indented `//` lines."""
    buf = []
    for number, raw in enumerate(text.splitlines(), 1):
        stripped = raw.strip()
        if stripped.startswith("//"):
            body = re.sub(r"^/{2,3}\s?", "", stripped)
            if body.startswith("  "):
                # An indented excerpt is data. It also ends the sentence before
                # it, so "(verified 2026-08-09):" does not borrow the excerpt's
                # numbers as its observed value.
                if buf:
                    yield buf
                    buf = []
                continue
            if body.strip():
                buf.append((number, body))
                continue
        if buf:
            yield buf
            buf = []
    if buf:
        yield buf


def sentences(joined):
    """(offset, sentence) pairs."""
    out, start = [], 0
    for m in re.finditer(r"[.!?](?=\s+[A-Z`\"(*⚠‘“])", joined):
        if ABBREVIATION.search(joined[max(0, m.start() - 6): m.end()]):
            continue
        out.append((start, joined[start:m.end()]))
        start = m.end() + 1
    out.append((start, joined[start:]))
    return out


def snapshots(joined, shapes=None):
    """(offset, shape, matched text) — at most one per sentence."""
    shapes = SHAPES if shapes is None else shapes
    found = []
    for offset, sentence in sentences(joined):
        if HISTORY_REFERENCE.search(sentence):
            continue
        for name, (pattern, needs_value) in shapes.items():
            hit = None
            for m in pattern.finditer(sentence):
                if needs_value and not VALUE.search(m.group("rest") or ""):
                    continue
                around = sentence[max(0, m.start() - 60): m.end()]
                if WHEN_CHECKED.search(around):
                    continue
                hit = (offset + m.start(), name, sentence[m.start():m.start() + 220])
                break
            if hit:
                found.append(hit)
                break
    return found


def line_at(paragraph, offset):
    consumed = 0
    for number, text in paragraph:
        if consumed + len(text) + 1 > offset:
            return number
        consumed += len(text) + 1
    return paragraph[-1][0]


def scan(text, shapes=None):
    """(offences, stale marker lines) for one family file's text."""
    offences, stale = [], []
    for paragraph in paragraphs(text):
        prose = [(n, POINTER_TOKEN.sub("", t)) for n, t in paragraph
                 if not t.startswith(MARKER)]
        markers = [(n, t) for n, t in paragraph if t.startswith(MARKER)]
        joined = " ".join(t for _, t in prose)
        hits = [(line_at(prose, offset), shape, matched)
                for offset, shape, matched in snapshots(joined, shapes)] if prose else []
        if markers and not hits:
            stale.extend(n for n, _ in markers)
            continue
        bare = [n for n, t in markers if not REASON.search(t)]
        for n in bare:
            offences.append((n, "no-reason", f"{MARKER} with no reason after it"))
        if markers and not bare:
            continue
        offences.extend(hits)
    if not HISTORY_POINTER.search(text):
        # A "History has …" sentence is exempt above. In a family with no pointer
        # there is no History for it to mean, so it is a way around the check.
        for paragraph in paragraphs(text):
            joined = " ".join(t for _, t in paragraph)
            m = HISTORY_REFERENCE.search(joined)
            if m:
                offences.append((line_at(paragraph, m.start()), "history-without-pointer",
                                 "says History has it, but the family has no History "
                                 "pointer"))
    return offences, stale


def review(root, shapes=None):
    """Everything the check knows, as data, so the tests can drive it."""
    missing = [d for d in (RECIPES, RECIPE_DATA) if not (root / d).is_dir()]
    found = {"missing": missing, "guarded": 0, "data": 0, "offences": [], "stale": []}
    if found["missing"]:
        return found
    paths = sorted(families.swift_family_files(root) + families.data_family_files(root),
                   key=lambda p: p.stem.lower())
    for path in paths:
        text = path.read_text(errors="replace")
        found["guarded"] += 1
        found["data"] += path.suffix == ".json5"
        rel = path.relative_to(root)
        offences, stale = scan(text, shapes)
        found["offences"].extend((rel, n, kind, matched) for n, kind, matched in offences)
        found["stale"].extend((rel, n) for n in stale)
    return found


def canary_problems(shapes=None):
    shapes = SHAPES if shapes is None else shapes
    problems = []
    for name in shapes:
        sentence = CANARIES.get(name)
        if sentence is None:
            problems.append(f"shape `{name}` has no canary sentence")
            continue
        names = [shape for _, shape, _ in snapshots(sentence, shapes)]
        if name not in names:
            problems.append(f"shape `{name}` no longer catches its canary: {sentence!r}")
    for sentence in ALLOWED_CANARIES:
        if snapshots(sentence, shapes):
            problems.append(f"an allowed sentence is now flagged: {sentence!r}")
    return problems


def main(root=None, minimum=100, shapes=None):
    root = root or pathlib.Path(__file__).resolve().parent.parent

    canaries = canary_problems(shapes)
    if canaries:
        for problem in canaries:
            print(f"✗ {problem}", file=sys.stderr)
        print("  The patterns no longer do what their canaries say. Fix SHAPES "
              "(or the exclusions) rather than the canary.", file=sys.stderr)
        return 1

    found = review(root, shapes)

    if found["missing"]:
        print(f"✗ {', '.join(found['missing'])} not under {root} — fix the path rather "
              "than scanning nothing.", file=sys.stderr)
        return 1
    if found["guarded"] < minimum:
        print(f"✗ only {found['guarded']} guarded recipe families — too few to "
              "be a real run.", file=sys.stderr)
        return 1
    # The floor above says nothing about WHICH families: a data family missed by
    # the listing while the Swift ones still clear it would pass. The goldens count
    # the families the binary loads (recipe_families.py).
    mismatch = families.reconcile(root, found["guarded"], "guarded recipe families")
    if mismatch:
        print(f"✗ {mismatch}", file=sys.stderr)
        return 1

    offences, stale = found["offences"], found["stale"]
    if not offences and not stale:
        print(f"✓ no dated snapshots in recipe comments — "
              f"{found['guarded']} families guarded ({found['data']} as .json5)")
        return 0

    for rel, line, kind, matched in offences:
        family = rel.stem
        if kind == "no-reason":
            print(f"✗ {rel}:{line}: `{MARKER}` with no reason — write "
                  f"`{MARKER} — <why>`", file=sys.stderr)
        elif kind == "history-without-pointer":
            print(f"✗ {rel}:{line}: {matched} — add "
                  f"`// History: docs/app-audits/{family}.md#历史与实测` and the "
                  "section, or drop the reference", file=sys.stderr)
        else:
            print(f"✗ {rel}:{line}: dated measurement in a recipe "
                  f"comment [{kind}]\n    …{matched}…\n"
                  f"    → docs/app-audits/{family}.md#历史与实测", file=sys.stderr)
    for rel, line in stale:
        print(f"✗ {rel}:{line}: `{MARKER}` here no longer exempts anything — "
              "delete it, or it silently exempts whatever is written next",
              file=sys.stderr)
    print(f"\n{len(offences)} offence(s), {len(stale)} stale exemption(s).\n"
          "Recipe comments hold the current contract; measurements go to History:\n"
          "  1. move the paragraph to docs/app-audits/<family>.md under "
          "`## 历史与实测` (format: docs/app-audits/README.md\n"
          "     §「从 recipe 注释迁出的历史」) and keep the conclusion in code;\n"
          "  2. make sure the family has  "
          "// History: docs/app-audits/<family>.md#历史与实测\n"
          "  3. a date that only dates a contract claim may stay as "
          "\"(checked <date>)\" or \"when checked (<date>; History has …)\".\n"
          "If the measurement really is the contract, add on a line of the same "
          "paragraph:\n"
          f"    {MARKER} — <why it must stay in code>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

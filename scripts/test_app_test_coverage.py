#!/usr/bin/env python3
"""Regression tests for `app_test_coverage`. Run by `make test`.

    python3 scripts/test_app_test_coverage.py

The fixtures are lines copied from real `scripts/app-tests.sh` logs, where a
stderr log line from the test process and a swift-testing record interleaved
mid-line and the gate reported a passing case as never run: on 2026-09-13 the log
line landed inside the record, on 2026-09-17 the record landed inside the log
line. Every case names the mutation it catches.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import app_test_coverage as atc  # noqa: E402

# os_log echo from Security, spliced mid-name (app-tests-16030.log).
SPLIT_BY_OS_LOG = (
    "✔ Test aCopyTha2026-09-13 19:21:20.342690+0800 xctest[16059:13752262] "
    "[logging-persist] cannot open file at line 53009 of [8fa8248e30]\n"
    "tBecameABetaReadsTheStore() passed after 0.007 seconds.\n"
)

# NSLog from the helper gate, spliced mid-name (app-tests-12802.log).
SPLIT_BY_NSLOG = (
    "✔ Test aWrappedBetaIsRetaggedFromTheStoreItRe2026-09-13 19:19:10.527912+0800 "
    "xctest[12903:13741876] duo-helper: rejected connection — no client requirement "
    "is installed on this listener\n"
    "ad() passed after 0.005 seconds.\n"
)

# The reverse: a whole record spliced into the tail of an NSLog line, the rest of
# the message on the next line (app-tests-781.log, 2026-09-17).
RECORD_INSIDE_NSLOG = (
    "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] duo-helper: reje"
    "✔ Test aFailedCheckKeepsItsChannelAcrossARescan() passed after 0.004 seconds.\n"
    "cted connection — no client requirement is installed on this listener\n"
)

# A log line on its own line, between intact records — must change nothing.
STANDALONE = (
    "✔ Test aThreeDayFloorReadsInDays() passed after 0.003 seconds.\n"
    "2026-09-13 19:21:38.379184+0800 xctest[16965:13755191] [logging-persist] cannot open file\n"
    "✔ Test anEmptyStoreIsNotTreatedAsFullyCovered() passed after 0.002 seconds.\n"
)


class SplicedLogLines(unittest.TestCase):
    """Mutation: make `ran_cases` match `RAN` on the raw text only (drop the
    `SPLICED_LOG_LINE.sub` half) → both split cases come back empty.
    Mutation: make it match on the stripped text only (drop the raw half) → the
    record inside the NSLog line is cut out with it and comes back empty.
    Mutation: loosen `SPLICED_LOG_LINE` to any text up to a newline (e.g.
    `r"[^\\n]*\\n"`) → the split record's first half is cut out too, and both
    split cases come back empty."""

    def test_a_record_split_by_os_log_is_rejoined(self):
        self.assertEqual(atc.ran_cases(SPLIT_BY_OS_LOG), {"aCopyThatBecameABetaReadsTheStore"})

    def test_a_record_split_by_nslog_is_rejoined(self):
        self.assertEqual(atc.ran_cases(SPLIT_BY_NSLOG), {"aWrappedBetaIsRetaggedFromTheStoreItRead"})

    def test_a_record_inside_an_nslog_line_is_kept(self):
        self.assertEqual(atc.ran_cases(RECORD_INSIDE_NSLOG),
                         {"aFailedCheckKeepsItsChannelAcrossARescan"})

    def test_a_standalone_log_line_changes_nothing(self):
        self.assertEqual(atc.ran_cases(STANDALONE),
                         {"aThreeDayFloorReadsInDays", "anEmptyStoreIsNotTreatedAsFullyCovered"})


class StillAGate(unittest.TestCase):
    """The repair must not invent passes.

    Mutation: drop BOTH the `[✔━] ` marker and the `passed` anchor from `RAN`
    → the started and failed cases are counted, including the failure spliced
    into a log line, which only the raw-text half of `ran_cases` sees whole.
    Dropping only one of them keeps this class green: either one rejects a whole
    `◇`/`✘` record. For torn records only the marker does; see
    `TornRecordsDoNotBorrowAVerdict`.
    """

    def test_a_case_that_only_started_is_not_counted(self):
        text = (
            "◇ Test aCaseThatHung() started.\n"
            "✔ Test anotherCase() passed after 0.001 seconds.\n"
        )
        self.assertEqual(atc.ran_cases(text), {"anotherCase"})

    def test_a_failed_case_is_not_counted(self):
        text = "✘ Test aFailingCase() failed after 0.001 seconds with 1 issue.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_failure_inside_a_log_line_is_not_counted(self):
        text = (
            "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] duo-helper: reje"
            "✘ Test aFailingCase() failed after 0.001 seconds with 1 issue.\n"
            "cted connection — no client requirement is installed on this listener\n"
        )
        self.assertEqual(atc.ran_cases(text), set())


# Prefix of a timestamped log line, as the test process writes it.
TS = "2026-09-17 17:08:17.095680+0800 xctest[1112:8721793] "


class TornRecordsDoNotBorrowAVerdict(unittest.TestCase):
    """A record torn by a log line must not take `passed` from the log line.

    Constructed, not copied from a log: nothing like these has been seen. Each
    one is a record that did NOT pass, glued to log text that ends in `passed`.
    The first two are the counterexamples from the review of #716.

    Mutation: drop the `[✔━] ` marker from `RAN` → all four are counted.
    Mutation: keep the marker for the raw text but match the stripped text with
    a marker-less pattern → only the third is counted, the one where cutting
    the log line out assembles `◇ Test foo() passed`.
    """

    def test_a_started_record_torn_at_its_paren_is_not_counted(self):
        text = "◇ Test foo(" + TS + "helper: probe (ok) passed\n) started.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_failed_record_torn_at_its_paren_is_not_counted(self):
        text = "✘ Test foo(" + TS + "check(x) passed\n) failed after 0.001 seconds with 1 issue.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_started_record_whose_tail_lands_in_a_log_line_is_not_counted(self):
        # Record head, log head, record tail, log tail. Cutting the log line out
        # (through the record's newline) leaves `◇ Test foo() passed`.
        text = "◇ Test foo(" + TS + "msg) started.\n) passed\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_marker_from_another_record_is_not_borrowed(self):
        text = "✔ Test bar() passed after 0.001 seconds.\n◇ Test foo(" + TS + "probe (ok) passed\n) started.\n"
        self.assertEqual(atc.ran_cases(text), {"bar"})


class SFSymbolsOutput(unittest.TestCase):
    """With SF Symbols on, swift-testing prints private-use characters instead of
    `✔`/`━`: pass U+10105B, pass with known issues U+100882, fail U+100884
    (`Event.Symbol._sfSymbolInfo`, swift-testing release/6.4.0). When it writes
    to a pipe it also turns ANSI mode on, which adds a second space after an SF
    glyph. The pass record below is copied from `make test` on 2026-09-17 with
    SWT_SF_SYMBOLS_ENABLED=1: the SwiftPM half printed every one of its 3483 pass
    records that way.

    The same run's xcodebuild half still printed `✔ Test`, even with the variable
    confirmed in xctest's environment (via TEST_RUNNER_SWT_SF_SYMBOLS_ENABLED).
    So this is defence for output the App tests weren't seen to produce.

    Mutation: drop U+10105B / U+100882 from `RAN`'s marker class → the two pass
    cases come back empty.
    Mutation: allow exactly one space after the marker → the real SwiftPM record
    comes back empty.
    Mutation: widen the marker to any non-space character → the torn SF failure
    is counted.
    """

    def test_an_sf_symbols_pass_written_to_a_pipe_is_counted(self):
        text = "\U0010105B  Test capCutReadsJoinBetaOutOfTheRealINI() passed after 0.013 seconds.\n"
        self.assertEqual(atc.ran_cases(text), {"capCutReadsJoinBetaOutOfTheRealINI"})

    def test_an_sf_symbols_pass_with_a_known_issue_is_counted(self):
        text = "\U00100882 Test foo(_:) with 2 test cases passed after 0.001 seconds with 1 known issue.\n"
        self.assertEqual(atc.ran_cases(text), {"foo"})

    def test_a_torn_sf_symbols_failure_is_not_counted(self):
        text = "\U00100884  Test foo(" + TS + "probe (ok) passed\n) failed after 0.001 seconds with 1 issue.\n"
        self.assertEqual(atc.ran_cases(text), set())


class ReadsUTF8WhateverTheLocale(unittest.TestCase):
    """The markers are non-ASCII, so a log read with the locale's encoding
    stops matching. Measured 2026-09-17: under LC_ALL=en_US.ISO8859-1 the gate
    reported 0 of 51 cases run, and under LC_ALL=C with PYTHONUTF8=0 it crashed
    reading the Swift sources. Which locales a host has is host state, so
    rather than switch locales this runs the gate with every implicit-encoding
    read turned into an error.

    Mutation: drop `encoding="utf-8"` from either `read_text` call in
    `app_test_coverage` → the subprocess exits non-zero with an EncodingWarning.
    """

    def test_the_gate_names_its_encoding_for_every_read(self):
        import subprocess
        import tempfile

        # EncodingWarning and `-X warn_default_encoding` are 3.10+; older
        # interpreters ignore both and this would pass without checking anything.
        self.assertGreaterEqual(sys.version_info[:2], (3, 10))
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Tests").mkdir()
            (root / "Tests" / "ZZFixtureTests.swift").write_text(
                "// — non-ASCII on purpose\n@Test func zzFixtureCase() {}\n", encoding="utf-8")
            (root / "app-tests.log").write_text(
                "✔ Test zzFixtureCase() passed after 0.001 seconds.\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "-X", "warn_default_encoding", "-W", "error::EncodingWarning",
                 str(pathlib.Path(atc.__file__)), str(root / "app-tests.log"), str(root / "Tests")],
                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], "1 1")


# A `get test-results tests` report, trimmed to the fields this reads. Copied in
# shape from the real bundle of a 2026-09-20 run (Xcode 27.0 27A266a,
# xcresulttool 25115, schema 0.4.0): cases nest under Test Plan -> bundle ->
# Test Suite, a parameterized case is one node spelled `foo(_:)` with child
# `Arguments` nodes, and `result` is a sibling of `name`.
def report(*cases):
    return {
        "testNodes": [{
            "nodeType": "Test Plan", "name": "DuoUpdater",
            "children": [{
                "nodeType": "Unit test bundle", "name": "DuoUpdaterAppTests",
                "children": [{
                    "nodeType": "Test Suite", "name": "HelperPeerGateTests",
                    "children": [
                        {"nodeType": "Test Case", "name": n, "result": r}
                        for n, r in cases
                    ],
                }],
            }],
        }],
    }


class ResultBundleIsTheVacuityGate(unittest.TestCase):
    """The structured source must still catch a case that did not execute.

    This is the property the whole gate exists for, and the .xcresult is the
    door through which it is easiest to lose: unlike the console, which simply
    has no record for a case that never ran, the bundle lists a disabled case
    by name anyway.

    MEASURED, not assumed. On 2026-09-20 `.disabled("mutation probe")` was put
    on `theClientRequirementIsPinnedForATeam` and `scripts/app-tests.sh` rerun.
    The bundle held 51 `Test Case` nodes for 51 declared cases — 50 `Passed`
    and that one `Skipped`, the disabled case present by name. A reader that
    counted nodes, or that ignored `result`, would have called the run complete
    while that case never executed. That is verbatim the first of the three
    counting bugs in the module docstring, walking back in through a new door.

    Mutation: drop `Skipped` from `DID_NOT_RUN` (or delete the
    `node.get("result") not in DID_NOT_RUN` test) → the first two cases here
    fail, and so does `test_a_disabled_case_is_reported_missing_end_to_end`.
    """

    def test_a_skipped_case_did_not_run(self):
        names = atc.names_from_test_report(
            report(("aRealCase()", "Passed"), ("aDisabledCase()", "Skipped")))
        self.assertEqual(names, {"aRealCase"})

    def test_a_whole_suite_of_skips_runs_nothing(self):
        names = atc.names_from_test_report(
            report(("one()", "Skipped"), ("two()", "Skipped")))
        self.assertEqual(names, set())

    def test_a_case_that_ran_and_failed_still_ran(self):
        # A failure already fails xcodebuild, and app-tests.sh exits before the
        # gate, so counting it here keeps "ran" meaning "executed", not "passed".
        names = atc.names_from_test_report(
            report(("aFailingCase()", "Failed"), ("anExpected()", "Expected Failure")))
        self.assertEqual(names, {"aFailingCase", "anExpected"})

    def test_a_parameterized_case_gives_its_declared_name(self):
        r"""Mutation: anchor the name match to empty parens (`([A-Za-z0-9_]+)\(\)`)
        → the parameterized case vanishes and is reported as never run, which is
        the third counting bug in the module docstring."""
        names = atc.names_from_test_report(
            report(("aMalformedTeamYieldsNoRequirement(_:)", "Passed")))
        self.assertEqual(names, {"aMalformedTeamYieldsNoRequirement"})

    def test_an_arguments_node_is_not_a_case_that_ran(self):
        """Only `Test Case` nodes answer "did it run", and the `Arguments`
        children of a parameterized case are the trap.

        Measured in the 2026-09-20 bundle: an `Arguments` node's `name` is the
        rendered argument (`"ZZFIXTURE"`, `"zzfixture0"`), and — unlike every
        container node — it carries NO `result` key at all. So the `Skipped`
        rule cannot reject it; only the `nodeType` test can. A suite
        parameterized over strings that look like Swift calls is all it takes
        for such a node to be spelled exactly like a case name, and a bogus
        name that collides with a declared one masks that case's absence.

        Mutation: drop the `nodeType == "Test Case"` test → `requirement` is
        counted as a case that ran, on a run where the only case was skipped.
        """
        parameterized = {
            "nodeType": "Test Case", "name": "aCaseOverCallSpellings(_:)",
            "result": "Skipped",
            "children": [
                # No `result` key, exactly as the real bundle writes them.
                {"nodeType": "Arguments", "name": "requirement(team:)"},
                {"nodeType": "Arguments", "name": "\"ZZFIXTURE\""},
            ],
        }
        report_with_args = {"testNodes": [{
            "nodeType": "Test Plan", "name": "DuoUpdaterAppTests",
            "result": "Passed", "children": [parameterized]}]}
        self.assertEqual(atc.names_from_test_report(report_with_args), set())

    def test_container_nodes_are_not_names(self):
        """The plan, the bundle and each suite carry `name` and `result` too.
        They cannot match the name pattern today — none of them has a `(` — so
        this pins the intent rather than a live failure."""
        names = atc.names_from_test_report(report(("only()", "Passed")))
        self.assertEqual(names, {"only"})


class ResultBundleFallsBackRatherThanLying(unittest.TestCase):
    """An unreadable bundle is evidence about the toolchain, not about the
    tests, so it must hand over to the console parser rather than report an
    empty run. A bundle that yields no cases is treated the same way: a
    genuinely empty run still fails the gate, because the console finds nothing
    either, but a schema change does not manufacture 51 false reds.

    Mutation: return `names` instead of `names or None` from
    `ran_cases_from_result_bundle` → an empty report stops falling back.
    """

    def test_a_missing_bundle_reads_as_unreadable(self):
        self.assertIsNone(
            atc.ran_cases_from_result_bundle(pathlib.Path("/nonexistent.xcresult")))

    def test_a_report_with_no_cases_yields_no_names(self):
        self.assertEqual(atc.names_from_test_report({"testNodes": []}), set())
        self.assertEqual(atc.names_from_test_report({}), set())


class EndToEnd(unittest.TestCase):
    """`main()` over a temp tree, driving the two sources against each other.

    `xcrun` is stubbed on PATH so this needs no Xcode: the stub prints a report
    we choose, which is the only way to exercise the subprocess path and the
    `--result-bundle` argument parsing on a machine without a toolchain.
    """

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        (self.root / "Tests").mkdir()
        (self.root / "Tests" / "ZZFixtureTests.swift").write_text(
            "@Test func caseOne() {}\n@Test func caseTwo() {}\n", encoding="utf-8")
        self.log = self.root / "app-tests.log"
        self.bundle = self.root / "app-tests.xcresult"
        self.bundle.mkdir()

    def write_log(self, *names):
        self.log.write_text(
            "".join("✔ Test %s() passed after 0.001 seconds.\n" % n for n in names),
            encoding="utf-8")

    def stub_xcrun(self, payload):
        """A `xcrun` on PATH that prints `payload`, or exits 1 when it is None."""
        import json
        import os
        import stat
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        script = bin_dir / "xcrun"
        if payload is None:
            body = "#!/bin/sh\nexit 1\n"
        else:
            blob = self.root / "report.json"
            blob.write_text(json.dumps(payload), encoding="utf-8")
            body = "#!/bin/sh\ncat %s\n" % blob
        script.write_text(body, encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        return os.pathsep.join([str(bin_dir), os.environ.get("PATH", "")])

    def run_gate(self, path_override=None, with_bundle=True):
        import os
        import subprocess
        env = dict(os.environ)
        if path_override:
            env["PATH"] = path_override
        argv = [sys.executable, str(pathlib.Path(atc.__file__))]
        if with_bundle:
            argv += ["--result-bundle", str(self.bundle)]
        argv += [str(self.log), str(self.root / "Tests")]
        out = subprocess.run(argv, capture_output=True, text=True,
                             encoding="utf-8", env=env)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.splitlines()

    def test_the_bundle_is_preferred_over_the_console(self):
        # The log is deliberately WRONG — it shows both cases passing — while
        # the bundle says one was skipped. If the bundle is preferred, the gate
        # reports the skip. Mutation: swap the preference in `main()` so the
        # console wins → this reports `2 2` with nothing missing.
        self.write_log("caseOne", "caseTwo")
        path = self.stub_xcrun(report(("caseOne()", "Passed"), ("caseTwo()", "Skipped")))
        lines = self.run_gate(path)
        self.assertEqual(lines[0], "2 1")
        self.assertEqual(lines[1], "caseTwo")
        self.assertEqual(lines[2], "result-bundle")

    def test_a_disabled_case_is_reported_missing_end_to_end(self):
        """The vacuity guard, whole: this is the failure the gate exists to
        catch. Mutation: drop `Skipped` from `DID_NOT_RUN` → nothing is
        reported missing, and `app-tests.sh` goes green on a run in which
        `caseTwo` never executed."""
        self.write_log("caseOne")
        path = self.stub_xcrun(report(("caseOne()", "Passed"), ("caseTwo()", "Skipped")))
        lines = self.run_gate(path)
        self.assertEqual(lines[0], "2 1")
        self.assertEqual(lines[1], "caseTwo")

    def test_an_empty_run_still_fails_the_gate(self):
        """Nothing ran at all: the bundle yields no cases, the gate falls back
        to a console log that is also empty, and BOTH declared cases come back
        missing. The fallback must not turn an empty run green.

        The source line is asserted too, because it is the only thing that
        distinguishes "no cases, so ask the log" from "no cases, so nothing
        ran": both give `2 0` here. Mutation: return `names` instead of
        `names or None` from `ran_cases_from_result_bundle` → the source reads
        `result-bundle` and an Xcode schema change would be indistinguishable
        from a suite that stopped running."""
        self.write_log()
        path = self.stub_xcrun(report())
        lines = self.run_gate(path)
        self.assertEqual(lines[0], "2 0")
        self.assertEqual(sorted(lines[1].split()), ["caseOne", "caseTwo"])
        self.assertEqual(lines[2], "console-log")

    def test_an_unreadable_bundle_falls_back_to_the_console(self):
        """xcresulttool exits non-zero — a broken, absent or restricted
        toolchain. The console log is complete, so the gate must go green on it
        rather than report both cases missing.

        Mutation: make `main()` treat a `None` from the bundle as an empty set
        instead of falling back → this reports `2 0` and CI reds on every run
        of a machine without xcresulttool."""
        self.write_log("caseOne", "caseTwo")
        path = self.stub_xcrun(None)
        lines = self.run_gate(path)
        self.assertEqual(lines[0], "2 2")
        self.assertEqual(lines[1], "")
        self.assertEqual(lines[2], "console-log")

    def test_garbage_from_xcresulttool_falls_back(self):
        """A schema this doesn't understand must not read as an empty run.
        Mutation: drop the `json.JSONDecodeError` guard → the gate crashes, and
        `app-tests.sh`'s `|| true` turns that into an empty `DECLARED`, which
        its own "found no @Test cases" branch reports as a broken gate."""
        import os
        import stat
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        script = bin_dir / "xcrun"
        script.write_text("#!/bin/sh\necho 'not json at all'\n", encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        self.write_log("caseOne", "caseTwo")
        lines = self.run_gate(
            os.pathsep.join([str(bin_dir), os.environ.get("PATH", "")]))
        self.assertEqual(lines[0], "2 2")
        self.assertEqual(lines[2], "console-log")

    def test_a_partial_report_from_a_failing_xcresulttool_is_not_trusted(self):
        """xcresulttool can print a well-formed but INCOMPLETE report and still
        exit non-zero — a half-written bundle after a crashed or killed run.
        The JSON parses, so the exit code is the only thing that rejects it.

        Here the report holds one of the two cases. Trusting it would report
        `caseTwo` as never run, which is a false red on a run whose console log
        shows both passing.

        Mutation: drop the `proc.returncode != 0` test → the gate reads the
        partial report, answers `2 1`, and fails the build on a green run.
        """
        import json
        import os
        import stat
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        blob = self.root / "partial.json"
        blob.write_text(json.dumps(report(("caseOne()", "Passed"))), encoding="utf-8")
        script = bin_dir / "xcrun"
        script.write_text("#!/bin/sh\ncat %s\nexit 1\n" % blob, encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        self.write_log("caseOne", "caseTwo")
        lines = self.run_gate(
            os.pathsep.join([str(bin_dir), os.environ.get("PATH", "")]))
        self.assertEqual(lines[0], "2 2")
        self.assertEqual(lines[2], "console-log")

    def test_no_bundle_argument_is_the_old_console_behaviour(self):
        self.write_log("caseOne", "caseTwo")
        lines = self.run_gate(with_bundle=False)
        self.assertEqual(lines[0], "2 2")
        self.assertEqual(lines[2], "console-log")


class TheSweepStillFindsNoFalseGreen(unittest.TestCase):
    """`scripts/sweep_app_test_coverage.py` is the console parser's own
    evidence: it tears a record and a log line at every position, interleaves
    them every way, and asserts that no ordering makes a non-passing case look
    like it ran. Running its quick mode here keeps that claim from rotting the
    way the uncommitted 2026-09-17 sweep did.

    Mutation: remove the `[✔━…]` marker class from `RAN` → the sweep reports
    false greens and exits non-zero.
    """

    def test_the_quick_sweep_reports_no_false_green(self):
        import subprocess
        out = subprocess.run(
            [sys.executable,
             str(pathlib.Path(atc.__file__).parent / "sweep_app_test_coverage.py"),
             "--quick"],
            capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("no false green", out.stdout)


class KnownConsoleMisses(unittest.TestCase):
    """The two interleaving orderings the console parser cannot recover.

    Pinned deliberately as MISSES, not as bugs awaiting a fix. Both are a pass
    record and a log line each torn in two, ordered so that the log line's own
    newline arrives after a piece of the record:

      log | record | log | record   — cutting the log line out takes the
                                      record's head with it
      record | log | record | log   — cutting it out takes the record's tail

    This is the shape behind the 2026-09-20 false red (CI run 35492361595).
    Recovering either one means allowing text between `)` and `passed` that the
    log line could have written, which is exactly how a torn non-passing record
    would borrow a verdict it never earned — so the marker/`Test `/name
    adjacency is not loosened to make them pass.

    Measured 2026-09-20 with `sweep_app_test_coverage.py`: three candidate
    repairs (stop the log-line cut at a marker; cut only the timestamp header;
    both) moved recall from 86.2% to 86.3% across 179040 torn texts built from
    one pass record against all ten log fixtures — nothing to buy here at any
    price. The full sweep puts the parser at 85.8% of 895200 torn texts with
    every miss in these two orderings. That is why the .xcresult is now the
    preferred source: it is not subject to any of this.

    If someone later makes these pass, they owe an argument for how the verdict
    still cannot be borrowed.
    """

    def test_a_record_whose_head_lands_in_an_unfinished_log_line_is_missed(self):
        text = TS + "msgA✔ Test foo() pasmsgB\nsed after 0.004 seconds.\n"
        self.assertEqual(atc.ran_cases(text), set())

    def test_a_record_torn_by_an_unfinished_log_line_is_missed(self):
        text = "✔ Test foo() p" + TS + "msgAassed after 0.004 seconds.\nmsgB\n"
        self.assertEqual(atc.ran_cases(text), set())


if __name__ == "__main__":
    unittest.main()

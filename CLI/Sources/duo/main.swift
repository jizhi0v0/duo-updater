import Foundation
import DuoKit

// duo — the command line face of DuoUpdater.
//
// Links the real `DuoUpdaterCore`, so every command runs the same code the
// menu-bar app does. Subcommands are added as the CLI grows; today only
// `verify` is wired.

let usage = """
usage: duo <command> [options]

commands:
  list          What is installed, without touching the network.
  check         What has an update, and how it would be applied.
  install       Apply updates, through the same engine the menu-bar app uses.
  doctor        Whether this machine can actually install anything, and what
                is missing if not.
  verify        Sweep the recipes against their live endpoints and report the
                ones that can no longer do their job.
  triage        Ask a model why the flagged recipes broke, and check its answer
                against the captured response before anyone reads it.
  reconcile     Turn a verify report into GitHub issues — one per broken recipe,
                closed automatically when it heals.
  help          Show this message.

list / check options:
  [<app>…]            Which apps, resolved as an install path, then a bundle id,
                      then a name prefix. An ambiguous prefix is an error, never
                      a guess. Omit for all of them.
  --json              One JSON object per line, so a slow check streams.
  --all               Include apps that are already up to date (implied by list).
  --include-hidden    Include apps you ignored or whose version you skipped.

  Both read the menu-bar app's own settings — same sources, same order, same
  ignore and skip lists — so a disagreement between duo and the app is a bug.
  `check` exits 1 when anything has an update, so `duo check && …` is usable in
  a script.

install options:
  [<app>…] | --all    Which apps. Resolved like check's. --all means every
                      update you would see in the app; a named app is installed
                      even if you had hidden it.
  --dry-run           Print the plan and stop. Exits 1 if there is work.
  --yes               Don't ask. Required when stdin isn't a terminal, so a
                      script never has consent assumed for it.
  --json              One JSON object per installed app.

  App Store updates are refused, not attempted: that route needs the privileged
  helper or the Accessibility API, neither of which a standalone binary has.
  Holds a machine-wide lock, so it exits rather than swapping a bundle while the
  menu-bar app is installing.

doctor options:
  --json              Machine-readable form of the same report.

  Exits 3 when App Management is not granted, since that is the permission the
  in-place install routes need and the one nobody guesses.

verify options:
  --only <text>       Restrict to recipes whose bundle id contains <text>.
                      Comma-separated for several. Without it all three
                      registries are swept (~150 requests, about 3 minutes).
  --vendor            Sweep only the vendor probe recipes.
  --github            Sweep only the GitHub release rules.
  --changelog         Sweep only the changelog recipes.
  --samples           Print the fetched body sample for each flagged recipe —
                      what you need to re-derive a broken pattern.
  --no-installed      Don't cross-check against locally installed apps. Implied
                      on a machine where nothing is installed (i.e. CI).
  --baseline <path>   Read and update the run-to-run baseline (version history,
                      failure streaks, issue numbers). Without it every sweep is
                      judged in isolation and nothing is remembered.
  --report <path>     Write the findings as JSON.
  --markdown <path>   Write the findings as Markdown.
  --max-concurrency N Hosts probed in parallel (default 4). One request at a
                      time per host regardless.

triage options:
  --report <path>     The JSON written by `duo verify --report`. Required.
  --baseline <path>   Used only to read failure streaks — never written.
  --out <path>        Where to write the suggestions. Required.
  --model <id>        Overrides the agent's model (default is declared in
                      .opencode/agent/duo-triage.md).
  --variant <effort>  Provider reasoning effort, e.g. max, high, minimal.
  --max-calls N       Hard cap on model calls in one run (default 20).
  --dry-run           List what would be asked about, call nothing.

  Runs opencode with no tools, in an empty temporary directory, and re-runs every
  proposed pattern through the app's own extractor before reporting it. A sweep
  with more than 30 actionable findings is treated as an outage and skipped.

reconcile options:
  --report <path>     The JSON written by `duo verify --report`. Required.
  --baseline <path>   The same baseline `verify` updated. Required — it holds the
                      issue numbers, so without it every run opens duplicates.
  --triage <path>     Optional suggestions from `duo triage`, folded into issue
                      bodies behind a collapsed, clearly-labelled block.
  --dry-run           Print what would happen and touch nothing.

  Uses the `gh` CLI, so it authenticates the same way you do locally and picks
  up GITHUB_TOKEN on a runner. Never opens more than 10 issues in one sweep.

exit codes:
  0  no recipe-level problems
  1  at least one recipe is degraded, broken for 2+ consecutive sweeps, or
     pointed at an endpoint that has been unreachable for 5+ consecutive sweeps
  2  usage error
"""

guard let args = Args(CommandLine.arguments) else {
    print(usage)
    exit(2)
}

switch args.subcommand {
case "list", "check":
    var options = Check.Options()
    options.queries = args.operands
    options.json = args.has("json")
    options.includeHidden = args.has("include-hidden")
    // `list` is the offline inventory, so "everything" is the only sensible
    // default; `check` shows what needs doing unless asked for the rest.
    options.checkForUpdates = (args.subcommand == "check")
    options.all = args.has("all") || args.subcommand == "list"
    exit(await Check.run(options))

case "install":
    var options = Install.Options()
    options.queries = args.operands
    options.all = args.has("all")
    options.dryRun = args.has("dry-run")
    options.assumeYes = args.has("yes")
    options.json = args.has("json")
    exit(await Install.run(options))

case "doctor":
    exit(Doctor.run(json: args.has("json")))

case "verify":
    var options = VerifyOptions()
    options.only = (args.value("only") ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    options.showSamples = args.has("samples")
    options.useInstalled = !args.has("no-installed")
    if let concurrency = args.int("max-concurrency") {
        options.hostConcurrency = max(1, concurrency)
    }
    // Naming any registry narrows to exactly those; naming none sweeps all.
    let selected = Registry.allCases.filter { args.has($0.rawValue) }
    if !selected.isEmpty { options.registries = Set(selected) }
    options.baselinePath = args.value("baseline").map { URL(fileURLWithPath: $0) }
    options.jsonPath = args.value("report").map { URL(fileURLWithPath: $0) }
    options.markdownPath = args.value("markdown").map { URL(fileURLWithPath: $0) }
    exit(await Verify.run(options))

case "triage":
    guard let report = args.value("report"), let out = args.value("out") else {
        die("triage needs --report <path> and --out <path>\n\n\(usage)", code: 2)
    }
    var triage = TriageOptions(
        reportPath: URL(fileURLWithPath: report),
        baselinePath: URL(fileURLWithPath: args.value("baseline") ?? "verify/baseline.json"),
        outPath: URL(fileURLWithPath: out),
        projectDir: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    triage.model = args.value("model")
    if let variant = args.value("variant") { triage.variant = variant }
    if let cap = args.int("max-calls") { triage.maxCalls = max(0, cap) }
    if let budget = args.int("budget") { triage.budget = TimeInterval(budget) }
    triage.dryRun = args.has("dry-run")
    exit(Triage.run(triage))

case "reconcile":
    guard let report = args.value("report"), let baseline = args.value("baseline") else {
        die("reconcile needs --report <path> and --baseline <path>\n\n\(usage)", code: 2)
    }
    exit(Reconcile.run(Reconcile.Options(
        reportPath: URL(fileURLWithPath: report),
        baselinePath: URL(fileURLWithPath: baseline),
        triagePath: args.value("triage").map { URL(fileURLWithPath: $0) },
        dryRun: args.has("dry-run"))))

case "help", "--help", "-h":
    print(usage)
    exit(0)

default:
    die("unknown command '\(args.subcommand)'\n\n\(usage)", code: 2)
}

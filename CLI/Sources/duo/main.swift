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
  verify        Sweep the recipes against their live endpoints and report the
                ones that can no longer do their job.
  reconcile     Turn a verify report into GitHub issues — one per broken recipe,
                closed automatically when it heals.
  help          Show this message.

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

reconcile options:
  --report <path>     The JSON written by `duo verify --report`. Required.
  --baseline <path>   The same baseline `verify` updated. Required — it holds the
                      issue numbers, so without it every run opens duplicates.
  --dry-run           Print what would happen and touch nothing.

  Uses the `gh` CLI, so it authenticates the same way you do locally and picks
  up GITHUB_TOKEN on a runner. Never opens more than 10 issues in one sweep.

exit codes:
  0  no recipe-level problems
  1  at least one recipe is degraded, or broken for 2+ consecutive sweeps
  2  usage error
"""

guard let args = Args(CommandLine.arguments) else {
    print(usage)
    exit(2)
}

switch args.subcommand {
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

case "reconcile":
    guard let report = args.value("report"), let baseline = args.value("baseline") else {
        die("reconcile needs --report <path> and --baseline <path>\n\n\(usage)", code: 2)
    }
    exit(Reconcile.run(Reconcile.Options(
        reportPath: URL(fileURLWithPath: report),
        baselinePath: URL(fileURLWithPath: baseline),
        dryRun: args.has("dry-run"))))

case "help", "--help", "-h":
    print(usage)
    exit(0)

default:
    die("unknown command '\(args.subcommand)'\n\n\(usage)", code: 2)
}

import Foundation
import DuoKit
import DuoUpdaterCore

// duo — the command line face of DuoUpdater.
//
// Links the real `DuoUpdaterCore`, so every command runs the same code the
// menu-bar app does — the same sources in the same order, the same install
// policy, the same ignore and skip rules. A disagreement between `duo` and the
// app is a bug, not a difference of opinion.

let usage = """
usage: duo <command> [options]

commands:
  list          What is installed, without touching the network.
  check         What has an update, and how it would be applied.
  install       Apply updates, through the same engine the menu-bar app uses.
  restart       Quit and relaunch apps whose running copy is stale.
  ignore        Hide an app from update checks. unignore undoes it.
  skip          Hide the version currently offered. unskip undoes it.
  backups       List the rollback points, or put one back.
  doctor        Whether this machine can actually install anything, and what
                is missing if not.
  requests      What DuoUpdater itself put on the network: which hosts, what
                for, and what it cost.
  events        The same activity as raw NDJSON, one event per line, for piping
                into jq or anything that draws.
  verify        Sweep the recipes against their live endpoints and report the
                ones that can no longer do their job.
  triage        Ask a model why the flagged recipes broke, and check its answer
                against the captured response before anyone reads it.
  reconcile     Turn a verify report into GitHub issues — one per broken recipe,
                closed automatically when it heals.
  help          Show this message. So do --help and -h after any command.

list / check options:
  [<app>…]            Which apps, resolved as an install path, then a bundle id,
                      then a name prefix. An ambiguous prefix is an error, never
                      a guess. Omit for all of them.
  --json              One JSON object per line, so a slow check streams. The
                      first line names the schema version.
  --all               Include apps that are already up to date (implied by list).
  --include-hidden    Include apps you ignored or whose version you skipped.
  --source <names>    Only apps answered by these sources, comma-separated:
                      sparkle, homebrew, vendor, github, "app store", toolbox,
                      testflight. `check` only — `list` asks no source, so it has
                      nothing to filter on.

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
  --route <names>     Only updates that would take these routes, comma-separated:
                      homebrew, installer, vendor, sparkle. A filter, NOT an
                      override — the route follows from the source, and forcing a
                      different one is how you install a build from the wrong
                      channel.
  --json              One JSON object per installed app, after a schema line.

  App Store updates are refused, not attempted: that route needs the privileged
  helper or the Accessibility API, neither of which a standalone binary has.
  Holds a machine-wide lock, so it exits rather than swapping a bundle while the
  menu-bar app is installing.

restart options:
  <app>…              Which apps. Resolved like check's. There is no --all: most
                      installed apps are not running, and "restart everything"
                      has no safe meaning.

  Quits gracefully — an app with unsaved work stays up and is reported rather
  than forced. An app that was in the foreground comes back to the foreground;
  one that was buried stays buried.

ignore / unignore / skip / unskip options:
  <app>…              Which apps, resolved like check's.
  --json              Machine-readable form.

  These are the only commands that write the app's preferences. skip records the
  version being offered now, so it runs a check first; a newer release than the
  skipped one still surfaces. The running menu-bar app re-reads both lists as
  soon as they change, so there is nothing to restart.

backups options:
  list                Every stored rollback point: app, version, when, size.
  restore <app>       Put a backed-up bundle back over the installed one.
  --yes               Don't ask before overwriting.
  --json              Machine-readable form.

  The signature check, retention and atomic swap all live in BackupStore, which
  this calls unmodified — nothing here loosens them. Like the app's own
  rollback, it does not refuse when the target is running; it restores and tells
  you to restart. A shared bundle id (Android Studio's channels, Thunderbird
  stable/esr) is ambiguous for a restore and is refused rather than guessed.

doctor options:
  --json              Machine-readable form of the same report.

  Also names apps that cannot be copied into the backup store, so you know
  before you update them that there is no way back. Walks the bundles of apps
  you do not own, which takes a couple of seconds.

  Exits 3 when App Management is not granted, since that is the permission the
  in-place install routes need and the one nobody guesses.

requests options:
  [summary]           Totals by purpose and by host. The default.
  recent [<n>]        The raw tail of the log: time, purpose, status, bytes,
                      address, host and path. Defaults to 50.
  reset               Discard the ledger.
  --all-clients       Also count requests `duo` made. Off by default — a
                      `duo verify` sweep is ~150 diagnostic requests, and folding
                      those into the totals misreports what the background
                      updater actually costs.
  --json              Machine-readable form.
  --yes               Don't ask before reset.

  Query strings are never recorded (a vendor activation key rides in one), and
  neither are headers or bodies. Two things it cannot see: Homebrew and the App
  Store fetch their own bytes, and our own Sparkle self-update downloads through
  the framework's session — that one is booked from the appcast's declared size
  and marked as declared rather than measured.

events options:
  --since <when>      ISO-8601 instant, or a relative 30m / 6h / 7d. Default 24h.
  --limit <n>         Newest n events. Default 200.
  --kind <name>       Only this event kind (today: request).
  --host <host>       Only this host.
  --purpose <name>    versioncheck, changelog, changelogimage, catalog, install,
                      selfupdate, other.
  --client <app|cli>  Only the menu-bar app's events, or only duo's.
  --filter <query>    The Requests tab's own syntax, e.g.
                      'host:api.github.com status:problems took>5s'.
                      Keys: host: app: purpose: status: client: size> took>;
                      bare words match host and path; a repeated key is OR.
                      Narrows to request events, so the install ledger drops out.
  --status            Where the store is, how big, what it covers, what it keeps.

  Every filter runs in SQL against an index, so narrowing is cheaper than
  dumping and filtering afterwards. Rows come out exactly as stored — the
  payload is not re-encoded through this binary, which matters because duo is
  installed separately from the app and is often the older of the two.

verify options:
  --only <text>       Restrict to recipes whose bundle id contains <text>.
                      Comma-separated for several. Without it all four
                      registries are swept (~150 requests, about 3 minutes).
  --vendor            Sweep only the vendor probe recipes.
  --github            Sweep only the GitHub release rules.
  --changelog         Sweep only the changelog recipes.
  --appstore          Sweep only the Mac App Store probe cases.
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
  --max-calls N       Hard cap on model calls in one run (default 6).
  --budget N          Seconds after which no new call is started (default 900).
                      A call already under way is left to finish, so the step
                      can overrun by up to one call. Findings it never reached
                      stay flagged and are picked up next sweep.
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

// `--help` and `-h` are answered before parsing, because `Args` refuses a
// leading dash as a subcommand: `duo --help` never reaches the switch below, and
// `duo verify --help` parses as a `verify` run carrying a flag nobody reads —
// which is to say the full ~150-request sweep.
if CommandLine.arguments.dropFirst().contains(where: { $0 == "--help" || $0 == "-h" }) {
    print(usage)
    exit(0)
}

guard let args = Args(CommandLine.arguments) else {
    print(usage)
    exit(2)
}

// Assigned by every branch, called only after the command line has been checked
// over — see the `unrecognised()` call below. Building the options and running
// them are deliberately two steps so that a typo costs nothing.
let run: () async -> Int32

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
    options.sources = args.list("source")
    // `list` never asks a source anything, so every row's source is unknown and
    // the filter would silently match nothing. Rejected rather than quietly
    // returning an empty list, which reads as "you have no Sparkle apps".
    if !options.sources.isEmpty && !options.checkForUpdates {
        die("--source needs a source to have answered; use `duo check --source …`", code: 2)
    }
    run = { await Check.run(options) }

case "install":
    var options = Install.Options()
    options.queries = args.operands
    options.all = args.has("all")
    options.dryRun = args.has("dry-run")
    options.assumeYes = args.has("yes")
    options.json = args.has("json")
    switch Install.routes(named: args.list("route")) {
    case .success(let routes): options.routes = routes
    case .failure(let failure): die(failure.description, code: 2)
    }
    run = { await Install.run(options) }

case "restart":
    var options = Restart.Options()
    options.queries = args.operands
    run = { await Restart.run(options) }

case "ignore", "unignore", "skip", "unskip":
    guard let action = Visibility.Action(rawValue: args.subcommand) else {
        die("unknown command '\(args.subcommand)'\n\n\(usage)", code: 2)
    }
    var options = Visibility.Options(action: action, queries: args.operands)
    options.json = args.has("json")
    run = { await Visibility.run(options) }

case "backups":
    // Which operation the operands name is worked out inside `run`, not here.
    // Other branches also refuse before the gate at the bottom — `--source`,
    // `--route`, and triage's required flags — but they refuse a value the user
    // typed after the flag they named. This is the only one that refuses an
    // *operand*, and an operand is where a mistyped flag's value lands: before
    // this, `duo backups --timeout 5` answered "unknown backups operation '5'",
    // blaming a `5` nobody typed on its own and never naming `--timeout`.
    let operands = args.operands
    let json = args.has("json")
    let assumeYes = args.has("yes")
    run = {
        let operation: Backups.Options.Operation
        switch operands.first {
        case "list", nil:
            operation = .list
        case "restore":
            guard operands.count == 2 else {
                die("backups restore needs exactly one app\n\n\(usage)", code: 2)
            }
            operation = .restore(app: operands[1])
        case let other?:
            die("unknown backups operation '\(other)'; expected list or restore", code: 2)
        }
        var options = Backups.Options(operation: operation)
        options.json = json
        options.assumeYes = assumeYes
        return await Backups.run(options)
    }

case "requests":
    let operands = args.operands
    let json = args.has("json")
    let allClients = args.has("all-clients")
    let assumeYes = args.has("yes")
    run = {
        let operation: Requests.Options.Operation
        switch operands.first {
        case "summary", nil:
            operation = .summary
        case "recent":
            // A bare `recent` means the default window; a number after it means
            // that many. Anything else is a typo, and guessing at one is how a
            // `duo requests recent 5o` silently becomes the default.
            if operands.count > 1 {
                guard let limit = Int(operands[1]), limit > 0 else {
                    die("requests recent takes a positive count, got '\(operands[1])'", code: 2)
                }
                operation = .recent(limit: limit)
            } else {
                operation = .recent(limit: 50)
            }
        case "reset":
            operation = .reset
        case let other?:
            die("unknown requests operation '\(other)'; expected summary, recent or reset", code: 2)
        }
        var options = Requests.Options(operation: operation)
        options.json = json
        options.allClients = allClients
        options.assumeYes = assumeYes
        return await Requests.run(options)
    }

case "events":
    var eventOptions = Events.Options()
    if let since = args.value("since") {
        guard let parsed = Events.parseSince(since) else {
            die("--since takes an ISO-8601 instant or a relative 30m / 6h / 7d, got '\(since)'",
                code: 2)
        }
        eventOptions.query.since = parsed
    } else {
        // A default window rather than none: this command exists to be piped, and
        // an unbounded default turns one screen into the whole retained history
        // the first time somebody runs it bare.
        eventOptions.query.since = Date().addingTimeInterval(-24 * 3600)
    }
    eventOptions.query.limit = args.int("limit") ?? 200
    eventOptions.query.kind = args.value("kind")
    eventOptions.query.host = args.value("host")
    if let purpose = args.value("purpose") {
        guard let parsed = RequestPurpose.allCases.first(where: {
            $0.rawValue.lowercased() == purpose.lowercased()
        }) else {
            die("unknown purpose '\(purpose)'; expected one of "
                + RequestPurpose.allCases.map(\.rawValue).joined(separator: ", "), code: 2)
        }
        eventOptions.query.purpose = parsed
    }
    if let client = args.value("client") {
        guard let parsed = RequestClient(rawValue: client.lowercased()) else {
            die("unknown client '\(client)'; expected app or cli", code: 2)
        }
        eventOptions.query.client = parsed
    }
    if let filter = args.value("filter") {
        let parsed = RequestQuery.parse(filter)
        // An unrecognised key would otherwise widen the dump while looking like
        // it narrowed it — the same failure the window prints in orange.
        if !parsed.ignoredKeys.isEmpty {
            die("unrecognised filter: \(parsed.ignoredKeys.joined(separator: ", "))", code: 2)
        }
        eventOptions.filter = parsed
    }
    eventOptions.showStatus = args.has("status")
    let events = eventOptions
    run = { await Events.run(events) }

case "doctor":
    let json = args.has("json")
    run = { await Doctor.run(json: json) }

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
    run = { await Verify.run(options) }

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
    run = { Triage.run(triage) }

case "reconcile":
    guard let report = args.value("report"), let baseline = args.value("baseline") else {
        die("reconcile needs --report <path> and --baseline <path>\n\n\(usage)", code: 2)
    }
    let reconcile = Reconcile.Options(
        reportPath: URL(fileURLWithPath: report),
        baselinePath: URL(fileURLWithPath: baseline),
        triagePath: args.value("triage").map { URL(fileURLWithPath: $0) },
        dryRun: args.has("dry-run"))
    run = { Reconcile.run(reconcile) }

case "help":
    print(usage)
    exit(0)

default:
    die("unknown command '\(args.subcommand)'\n\n\(usage)", code: 2)
}

// Nothing has run yet: every branch above only reads flags and builds options.
// A flag no branch read is a typo, and a typo that parses as "absent" is how
// `duo verify --githubb` turns a one-recipe check into the whole sweep.
if let problem = args.unrecognised() {
    die("\(problem)\n\ntry `duo \(args.subcommand) --help`", code: 2)
}

let status = await run()
// The store batches its writes, and a CLI process exits long before the
// coalescing timer would fire. Only when something was actually recorded: a
// command that touched no network should not open a database just to close it.
if EventStore.hasRecorded { await EventStore.shared.flush() }
// Same shape, same reason: the GitHub validator store coalesces its writes over
// two seconds, and a `duo check <app>` is gone in milliseconds — without this
// its memos would never reach disk and every run would fetch unconditionally.
// Guarded like the event store: a command that never built a checker should
// not load the file just to write it back.
if GitHubConditionalCache.hasShared { await GitHubConditionalCache.shared.flush() }
exit(status)

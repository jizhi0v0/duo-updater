import Foundation
import os

/// Central logging for traceability. Every category shares one subsystem, so the
/// whole app's activity can be pulled after the fact with:
///
///   log show --predicate 'subsystem == "com.duoupdater.app"' --last 1h --info --debug
///
/// or streamed live with:
///
///   log stream --predicate 'subsystem == "com.duoupdater.app"' --info --debug
///
/// or filtered in Console.app by that subsystem. `--info`/`--debug` are needed
/// because the unified log keeps those levels off by default.
///
/// Levels we use:
///   • `.debug`  — per-source hits/misses, request URLs, HTTP statuses (verbose,
///                 the breadcrumbs you want when reconstructing one check).
///   • `.info`   — milestones: a scan finished, an update found, an install
///                 stage advanced.
///   • `.notice` — the default level, and the lowest one the unified log keeps
///                 ON DISK for a third-party subsystem: `.debug` and `.info` are
///                 memory-only and gone by the time anyone goes looking. Use it
///                 for the handful of lines that have to survive to explain a
///                 state the user can still see — why a row stopped answering,
///                 say — without being an `.error` in their face.
///   • `.error`  — a source threw, an install failed: the things that turn into
///                 an `.error` row or a swallowed surprise.
///
/// Privacy: the bundle ids, app names, versions and (public) URLs we log are not
/// secrets, so they're interpolated as `.public` to stay readable — os_log
/// redacts dynamic strings to `<private>` otherwise. Tokens and credentials are
/// never passed to a logger.
public enum Log {
    public static let subsystem = "com.duoupdater.app"

    /// Disk scan: which bundles were discovered or filtered out.
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    /// Update engine: per-app, per-source resolution and the final verdict.
    public static let check = Logger(subsystem: subsystem, category: "check")
    /// Individual sources: the network calls and parsing behind a check.
    public static let source = Logger(subsystem: subsystem, category: "source")
    /// Install/restart pipeline: download, verify, swap, relaunch.
    public static let install = Logger(subsystem: subsystem, category: "install")
    /// App/UI lifecycle: refresh runs, retries, user-driven actions.
    public static let app = Logger(subsystem: subsystem, category: "app")
    /// Changelog view: which recipe/source rendered, load successes and failures.
    public static let changelog = Logger(subsystem: subsystem, category: "changelog")
}

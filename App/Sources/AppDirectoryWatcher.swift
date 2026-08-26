import Foundation
import CoreServices

/// Watches the app install directories for on-disk changes and fires a debounced
/// callback. We use it to notice a *background* self-update — Chrome's Keystone
/// swapping in a new framework version, a Sparkle/Squirrel app replacing its own
/// bundle, `brew upgrade` — and flip the menu-bar **Relaunch** badge promptly,
/// instead of waiting for the user to open the menu or for the next networked
/// check (which, on a "Daily" frequency, could be ~24h away).
///
/// One FSEvents stream reports directory-level changes across each watched
/// subtree, which is all we need: any change under `/Applications` just means
/// "rescan disk". The callback is a network-free `refreshLocal` on the model.
///
/// `@unchecked Sendable`: all mutable state (`stream`, `pending`) is touched only
/// on the private serial `queue` — the FSEvents callback is dispatched there, and
/// `start`/`stop` hop onto it — so there's no concurrent access despite the class
/// being passed to the C stream via an unmanaged pointer. (Same justification as
/// `VendorProbeSource.RedirectBlocker`.)
final class AppDirectoryWatcher: @unchecked Sendable {
    private let paths: [String]
    private let debounce: TimeInterval
    private let rearmInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.duoupdater.appdirwatcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var rearmTimer: DispatchSourceTimer?

    /// - debounce: a Keystone/ShipIt swap touches many files over a couple of
    ///   seconds; we wait this long after the *last* event before rescanning so a
    ///   single swap triggers one rescan, not dozens.
    /// - rearmInterval: how often to tear the stream down and rebuild it (see
    ///   `rearm`). A live stream is indistinguishable from a dead one — FSEvents
    ///   reports nothing either way — so we don't try to detect the failure, we just
    ///   periodically replace the stream.
    init(
        paths: [String],
        debounce: TimeInterval = 2,
        rearmInterval: TimeInterval = 900,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.paths = paths
        self.debounce = debounce
        self.rearmInterval = rearmInterval
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
            self?.armRearmTimer()
        }
    }

    /// Rebuild the FSEvents stream from scratch, then fire one `onChange`.
    ///
    /// A stream can stop delivering while the process stays perfectly healthy — an
    /// observed instance ran for 90 minutes with an idle main thread, no wedged
    /// work, and not one event from either watched root; a relaunch fixed it
    /// instantly. Nothing in the FSEvents API reports that state, so recovery can't
    /// be conditional: we replace the stream on a timer and on wake, and rescan
    /// right after (the stop→start window loses events, and so does a sleep, so the
    /// rescan is what guarantees we never sit on a stale list).
    func rearm() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopStreamOnQueue()
            self.startOnQueue()
            self.coalesce()
        }
    }

    /// Re-arm on a slow cadence so a silently-dead stream self-heals within one
    /// interval instead of lasting the whole launch.
    private func armRearmTimer() {
        guard rearmTimer == nil, rearmInterval > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + rearmInterval, repeating: rearmInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.stopStreamOnQueue()
            self.startOnQueue()
            self.coalesce()
        }
        rearmTimer = timer
        timer.resume()
    }

    private func startOnQueue() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        // C callback: recover `self` from the context pointer and coalesce. Runs on
        // `queue` (set below), so touching mutable state here is safe.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<AppDirectoryWatcher>.fromOpaque(info)
                .takeUnretainedValue()
                .coalesce()
        }
        // Latency 1s lets FSEvents batch a burst before calling us; our own
        // `debounce` then waits for the swap to fully settle. `IgnoreSelf` drops
        // events from our *own* in-place installs (those already trigger a refresh
        // on the install path); `NoDefer` delivers the first event promptly.
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf)
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Debounce on our own queue: a flurry of file events collapses into a single
    /// `onChange` once changes stop for `debounce` seconds.
    private func coalesce() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.rearmTimer?.cancel()
            self.rearmTimer = nil
            self.stopStreamOnQueue()
        }
    }

    /// Tear down the stream and any queued rescan. Shared by `stop` and the re-arm
    /// paths, which rebuild right after.
    private func stopStreamOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        pending?.cancel()
        pending = nil
    }
}

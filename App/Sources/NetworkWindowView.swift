import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DuoUpdaterCore

/// Everything Duo Updater put on the network, in one window with two tabs.
///
/// **Downloads** is the per-app ledger: what each update cost as a file on disk.
/// **Requests** is the log itself: every fetch, filterable.
///
/// One window because they are one question asked at two altitudes, and the
/// numbers only make sense beside each other — the same download is 84 MB of
/// file and rather more than that of socket, and a reader who meets those two
/// figures in two different places reads one of them as a bug.
///
/// The request log used to be a pane in the workbench, which was the wrong home
/// for it: every other row there is one app, and nothing in the log is. It also
/// left the sidebar with a selection no list row could match, so arrowing off it
/// jumped the detail pane somewhere else.
struct NetworkWindowView: View {
    /// Unchanged from when this was the Download Traffic window. The identifier
    /// is what AppKit restores saved frames against and what `surfaceWindow`
    /// looks up, so renaming it would cost every existing user their window
    /// position to no visible benefit.
    static let windowID = "traffic"

    @Bindable var model: AppListModel
    @State private var tab: Tab = .downloads
    /// Owned here, not by the pane: switching tabs destroys the pane, and a
    /// filter that evaporated when you glanced at Downloads would have to be
    /// retyped every time.
    @State private var filter = RequestLogFilter()

    enum Tab: String, CaseIterable, Identifiable {
        case downloads, requests
        var id: String { rawValue }

        var label: String {
            switch self {
            case .downloads: return String(localized: "Downloads")
            case .requests:  return String(localized: "Requests")
            }
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .downloads: TrafficLedgerPane(model: model)
            case .requests:
                // Values and closures, not the model: `AppListModel.init`
                // registers for notifications, starts timers and installs a
                // filesystem watcher, so a pane that took it could not be drawn
                // by anything but the running app — and a pane nothing can
                // render offline is a pane nobody looks at until it ships.
                RequestLogPane(
                    filter: $filter,
                    hasLoaded: model.requestLogLoaded,
                    summary: model.requestSummary,
                    events: model.requestLog,
                    retainedEvents: model.retainedEventCount,
                    storeBytes: model.eventStoreBytes,
                    onQuery: { await model.reloadRequestLog($0) },
                    onReset: { query in Task { await model.resetRequestLog(query) } },
                    onExport: { query in export(query) },
                    onChangeToken: { await model.requestChangeToken() })
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        // Read once as soon as the window exists, not when the Requests tab is
        // first shown. Opening on Downloads and switching over used to start
        // from nothing and fill in — the read takes a moment, and the moment was
        // visible.
        .task {
            guard !model.requestLogLoaded else { return }
            await model.reloadRequestLog(RequestQuery.window(""))
        }
        .toolbar {
            // Centred in the title bar, and the same control the ledger's own
            // Size / Downloads / Recent sort uses — one switching idiom in the
            // window rather than two that look alike and behave differently.
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// Writes the matching rows exactly as stored, one JSON object per line —
    /// the same shape `duo events` emits, so anything reading one reads both.
    private func export(_ query: RequestQuery) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "duo-requests.ndjson"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let text = await model.exportRequestLog(query)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

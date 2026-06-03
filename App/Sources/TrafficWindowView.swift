import SwiftUI
import AppKit
import DuoUpdaterCore

/// The "流量统计" window — per-app download traffic, tracked to the byte.
///
/// Every update we install ourselves (Sparkle, Vendor, GitHub, pkg) reports the
/// exact bytes it transferred; this lists those per app, heaviest first, with a
/// grand total in the header. Homebrew updates aren't listed: `brew` downloads
/// them itself, so we never measure those bytes (counting only what we saw keeps
/// every number exact).
struct TrafficWindowView: View {
    static let windowID = "traffic"

    @Bindable var model: AppListModel
    @State private var selection: String?

    private var stats: [AppTrafficStat] { model.trafficStats }

    private var selected: AppTrafficStat? {
        stats.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
        } detail: {
            if let selected {
                TrafficDetail(stat: selected).id(selected.id)
            } else {
                ContentUnavailableView(
                    "Select an app",
                    systemImage: "chart.bar.fill",
                    description: Text("Pick an app to see its download history.")
                )
            }
        }
        .navigationTitle("Traffic")
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if stats.isEmpty {
                ContentUnavailableView(
                    "No downloads yet",
                    systemImage: "arrow.down.circle",
                    description: Text("Traffic appears here after you install an update.")
                )
            } else {
                List(stats, selection: $selection) { stat in
                    TrafficSidebarRow(stat: stat).tag(stat.id)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteFormat.string(model.trafficTotalBytes))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text("\(stats.count) app\(stats.count == 1 ? "" : "s") · \(model.trafficTotalBytes) bytes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// One app's row in the traffic sidebar: icon, name, total, and download count.
private struct TrafficSidebarRow: View {
    let stat: AppTrafficStat

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.icon(for: stat.appID))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.appName)
                    .lineLimit(1)
                Text("\(stat.updateCount) download\(stat.updateCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormat.string(stat.totalBytes))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// The detail pane: one app's per-update download history, each row showing the
/// version transition, source, exact byte count, and date.
private struct TrafficDetail: View {
    let stat: AppTrafficStat

    /// Newest event first.
    private var events: [TrafficEvent] {
        stat.events.sorted { $0.date > $1.date }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(nsImage: AppIconCache.icon(for: stat.appID))
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.appName).font(.title3.weight(.semibold))
                        Text("\(ByteFormat.string(stat.totalBytes)) · \(stat.totalBytes) bytes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Divider()

                ForEach(events, id: \.self) { event in
                    eventRow(event)
                    Divider()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func eventRow(_ event: TrafficEvent) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(versionTransition(event))
                    .font(.callout)
                HStack(spacing: 6) {
                    if let source = event.sourceName {
                        Text(source)
                    }
                    Text(Self.dateFormatter.string(from: event.date))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(event.bytes) bytes")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func versionTransition(_ event: TrafficEvent) -> String {
        switch (event.fromVersion, event.toVersion) {
        case let (from?, to?): return "\(from) → \(to)"
        case let (nil, to?): return to
        case let (from?, nil): return from
        case (nil, nil): return "Update"
        }
    }
}

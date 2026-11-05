import SwiftUI
import DuoUpdaterCore

struct AutomaticUpdateEventsPane: View {
    @State private var events: [DuoEvent] = []

    private func statusLabel(_ status: String?) -> String {
        switch status {
        case "started": String(localized: "Automatic update started")
        case "installed": String(localized: "Automatically updated")
        case "deferred": String(localized: "Automatic update deferred")
        default: String(localized: "Automatic update did not complete")
        }
    }

    var body: some View {
        List {
            if events.isEmpty {
                Text("No automatic update activity yet.").foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                if case .unknown(_, let json) = event.payload,
                   let data = json.data(using: .utf8),
                   let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fields["appName"] ?? "").fontWeight(.medium)
                            Spacer()
                            Text(event.date, style: .date)
                            Text(event.date, style: .time)
                        }
                        Text("\(fields["fromVersion"] ?? "") → \(fields["toVersion"] ?? "") · \(statusLabel(fields["status"]))")
                        if let reason = fields["reason"], !reason.isEmpty { Text(reason) }
                    }
                    .textSelection(.enabled)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                events = await EventStore.shared.events(.init(kind: "automaticUpdate", limit: 200))
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

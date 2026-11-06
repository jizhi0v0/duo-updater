import SwiftUI
import DuoUpdaterCore

struct AutomaticUpdateEventsPane: View {
    @State private var events: [DuoEvent] = []
    @State private var confirmsClear = false
    @State private var report: String?
    @State private var exportError: String?

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
            Text("Deferral is temporary. Eligible updates are reconsidered on a later scheduled pass; other work or network restrictions may delay it.").foregroundStyle(.secondary)
            if events.isEmpty {
                Text("No automatic update activity yet.").foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                if let fields = AutomaticUpdateDiagnostics.fields(event) {
                    VStack(alignment: .leading, spacing: 4) {
                        if fields["status"] == "diagnostics" {
                            DisclosureGroup("Local process diagnostics") {
                                Text(fields["diagnostics"] ?? "[]")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                            }
                        } else {
                            HStack {
                                Text(fields["appName"] ?? "").fontWeight(.medium)
                                Spacer()
                                Text(event.date, style: .date)
                                Text(event.date, style: .time)
                            }
                            Text("\(fields["fromVersion"] ?? "") → \(fields["toVersion"] ?? "") · \(statusLabel(fields["status"]))")
                            if let reason = fields["reason"], !reason.isEmpty { Text(reason) }
                            if fields["recoveredFrom"]?.isEmpty == false {
                                Text("A later attempt recovered and installed the update.").foregroundStyle(.secondary)
                            }
                        }
                        if let pass = fields["passID"] {
                            DisclosureGroup("Attempt details") {
                                Text("Pass: \(pass)")
                                if let attempt = fields["attemptID"] { Text("Attempt: \(attempt)") }
                                if let retry = fields["retryOf"], !retry.isEmpty { Text("Previous attempt: \(retry)") }
                                if let ids = fields["diagnosticIDs"], !ids.isEmpty { Text("Diagnostics: \(ids)") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.textSelection(.enabled)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("Activity is kept for 90 days, up to 10,000 records. Showing the latest 200.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Review sanitized report…") {
                    report = AutomaticUpdateDiagnostics.sanitizedReport(events)
                }
                Button("Clear activity…") { confirmsClear = true }
            }.padding()
        }
        .sheet(isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review sanitized report").font(.headline)
                Text("Contains aggregate outcomes and process probe results from the displayed records. App names, paths, process IDs and activity times are omitted. Nothing is sent automatically.")
                ScrollView { Text(report ?? "").font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                if let exportError { Text(exportError).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { report = nil }
                    Button("Save report…") { saveReport() }
                }
            }.padding().frame(width: 650, height: 480)
        }
        .confirmationDialog("Clear automatic update activity?", isPresented: $confirmsClear) {
            Button("Clear activity", role: .destructive) {
                Task {
                    await EventStore.shared.resetAutomaticUpdates()
                    events = await EventStore.shared.events(.init(kind: "automaticUpdate", limit: 200))
                }
            }
        } message: {
            Text("Request logs and permanent install history will be kept.")
        }
        .task {
            while !Task.isCancelled {
                events = await EventStore.shared.events(.init(kind: "automaticUpdate", limit: 200))
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private func saveReport() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "automatic-update-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
            self.report = nil
        } catch { exportError = error.localizedDescription }
    }
}

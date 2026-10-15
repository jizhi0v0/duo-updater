import SwiftUI
import AppKit
import DuoUpdaterCore

/// The report for one failed update, shown in full and editable, with two ways
/// to send it: a pre-filled GitHub issue opened in the browser, or a new email
/// with the report attached. Nothing leaves the Mac from here — both open
/// something the user reads and sends themselves.
///
/// Its own window rather than a sheet, so it opens from the popover row (which
/// dismisses) as well as from the workbench and Settings. Shows
/// `AppListModel.failureReportDraft`.
struct FailureReportView: View {
    static let windowID = "failure-report"

    @Bindable var model: AppListModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var text = ""
    @State private var emailUnavailable = false

    /// The report text for `failure` as Core builds it, with this build's
    /// version. Shared with Diagnostics' Copy Report.
    static func reportText(for failure: InstallFailureEvent, at date: Date) -> String {
        let version = AppListModel.runningSelfVersion ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return InstallFailureReport.text(
            for: failure, at: date,
            duoUpdaterVersion: build.map { "\(version) (\($0))" } ?? version)
    }

    var body: some View {
        Group {
            if let event = model.failureReportDraft, let failure = event.failure {
                form(failure)
                    // Rebuilt when a different failure is opened into the same window.
                    .task(id: event.id) {
                        text = Self.reportText(for: failure, at: event.date)
                        emailUnavailable = false
                    }
            } else {
                Text("No report is open.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func form(_ failure: InstallFailureEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a failed update")
                .font(.title3.weight(.semibold))
            Text("Nothing is sent until you choose how below. You can edit the report first — remove anything you’d rather not share.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if emailUnavailable {
                Text("No email app is set up on this Mac. Send the report to \(InstallFailureReport.emailRecipient), or open a GitHub issue instead.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Toggle("Don’t ask again", isOn: Binding(
                    get: { !model.prefs.offerFailureReports },
                    set: { model.prefs.offerFailureReports = !$0 }))
                    .help("Stop offering to report failed updates. Turn it back on in Settings → Diagnostics.")
                Spacer()
                Button("Cancel") { dismissWindow(id: Self.windowID) }
                    .keyboardShortcut(.cancelAction)
                Button("Email…") { email(failure) }
                    .help("Opens a new message to \(InstallFailureReport.emailRecipient) with the report attached.")
                Button("Open GitHub Issue…") {
                    openURL(InstallFailureReport.issueURL(
                        title: InstallFailureReport.title(for: failure), body: text))
                    dismissWindow(id: Self.windowID)
                }
                .keyboardShortcut(.defaultAction)
                .help("Opens a new issue on GitHub with the report filled in. Needs a GitHub account.")
            }
        }
        .padding(20)
    }

    /// A new message in the user's mail app, addressed and with the report
    /// attached as a text file (and in the body, so it reads without opening
    /// the file). The user sends it; this only opens it.
    private func email(_ failure: InstallFailureEvent) {
        guard let service = NSSharingService(named: .composeEmail),
              let file = try? writeAttachment(for: failure)
        else { emailUnavailable = true; return }
        let items: [Any] = [text, file]
        guard service.canPerform(withItems: items) else { emailUnavailable = true; return }
        service.recipients = [InstallFailureReport.emailRecipient]
        service.subject = InstallFailureReport.title(for: failure)
        service.perform(withItems: items)
        dismissWindow(id: Self.windowID)
    }

    /// The edited report as `<App> failure report.txt` in a folder of its own
    /// under the temporary directory, so the attachment carries a readable name.
    private func writeAttachment(for failure: InstallFailureEvent) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdater Report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = failure.appName.replacingOccurrences(of: "/", with: "-")
        let file = folder.appendingPathComponent("\(name) failure report.txt")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

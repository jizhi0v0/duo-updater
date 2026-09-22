import SwiftUI
import AppKit
import DuoUpdaterCore

/// Onboarding for the `.xcode` install route's sign-in session (Option C):
/// DuoUpdater signs in to developer.apple.com in its own web view and holds the
/// session itself, because Xcode betas and RCs sit behind an Apple ID and there
/// is no token or API key to enter instead. This page exists so the user always
/// knows where that access lives and how to take it back.
struct XcodeSettingsPage: View {
    /// Observed directly: the hourly check and a row's "Sign In…" change it while
    /// this page is open.
    private var session: AppleDeveloperSession { .shared }
    private var isSignedIn: Bool { session.isSignedIn }
    private var isExpired: Bool { session.signInNeed == .expired }
    @State private var busy = false
    @State private var feedback: Feedback?
    @State private var confirmingSignOut = false
    private var downloads: XcodeDownloadCenter { .shared }
    @State private var showBetas = true
    @State private var showAll = false

    /// How many builds the list shows before "Show All".
    private static let collapsedCount = 8

    /// No `.signedIn` case: the status line itself flips to "Signed in", and a
    /// second green "Signed in" beside it only repeated it.
    private enum Feedback: Equatable {
        case signedOut
        case cancelled
    }

    var body: some View {
        SettingsPage(section: .xcode) {
            SettingsCard(
                header: "Apple Developer sign-in",
                headerInfo: "DuoUpdater stores your Apple Developer sign-in session — the same one developer.apple.com already keeps in a cookie — so it can download Xcode betas and release candidates on your behalf. It's kept in the Keychain on this Mac, never synced to iCloud or anywhere else, and only ever sent to *.apple.com — Apple's developer, sign-in, and download servers.",
                footer: "This is what lets DuoUpdater download Xcode betas and release candidates for one-click updates. Without it, DuoUpdater can still tell you a new version exists, but you'll need to download it yourself. Apple can end the session on its side at any time. DuoUpdater asks Apple once an hour whether it still holds; if it has ended, the Xcode row asks you to sign in again."
            ) {
                statusRow
                SettingsDivider()
                actionsRow
            }
            downloadCard
        }
        .task { await refresh() }
        .task { await downloads.loadIfNeeded() }
        .confirmationDialog(
            "Sign Out and Clear Session?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out and Clear", role: .destructive) { Task { await signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also forgets that Apple trusts this Mac, so your next sign-in will ask for a verification code again.")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(isExpired ? .red : .primary)
                if isSignedIn, let confirmed = session.lastConfirmed {
                    Text("Apple last confirmed it \(confirmed.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            statusFeedback
        }
        .settingsRow()
    }

    @ViewBuilder private var statusIcon: some View {
        if isExpired {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if isSignedIn {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "seal").foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        if isExpired { return String(localized: "Sign-in expired") }
        return isSignedIn ? String(localized: "Signed in") : String(localized: "Not signed in")
    }

    @ViewBuilder private var statusFeedback: some View {
        switch feedback {
        case .signedOut:
            Label("Session cleared", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case .cancelled:
            Label("Sign-in cancelled", systemImage: "xmark.circle")
                .foregroundStyle(.secondary).font(.callout)
        case nil:
            EmptyView()
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            if isExpired {
                Button("Sign In…") { Task { await signIn() } }
                    .settingsGlassButton(prominent: true)
                    .disabled(busy)
            }
            if isSignedIn {
                Button("Sign Out and Clear…", role: .destructive) { confirmingSignOut = true }
                    .disabled(busy)
            } else {
                Button("Sign In…") { Task { await signIn() } }
                    .settingsGlassButton(prominent: true)
                    .disabled(busy)
            }
            Spacer(minLength: 8)
            ProgressView()
                .controlSize(.small)
                .opacity(busy ? 1 : 0)
        }
        .settingsRow()
    }

    // MARK: - Download Xcode

    private var shownItems: [XcodeDownloadItem] {
        downloads.items.filter { showBetas ? $0.isPrerelease : !$0.isPrerelease }
    }

    private var downloadCard: some View {
        SettingsCard(
            header: "Download Xcode",
            footer: "Saves the Xcode archive (.xip) to your Downloads folder — open it to expand Xcode, then move it where you like. Nothing is installed or replaced. Uses your Apple Developer sign-in; you'll be asked to sign in first if needed."
        ) {
            HStack {
                Picker("", selection: $showBetas) {
                    Text("Betas & RCs").tag(true)
                    Text("Releases").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .settingsRow()
            if downloads.loading && downloads.items.isEmpty {
                SettingsDivider()
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading versions…").foregroundStyle(.secondary)
                }
                .settingsRow()
            } else if let error = downloads.loadError, downloads.items.isEmpty {
                SettingsDivider()
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Try Again") { Task { await downloads.loadIfNeeded() } }
                }
                .settingsRow()
            } else {
                let items = shownItems
                ForEach(showAll ? items : Array(items.prefix(Self.collapsedCount))) { item in
                    SettingsDivider()
                    downloadRow(item)
                }
                if items.count > Self.collapsedCount {
                    SettingsDivider()
                    Button(showAll ? String(localized: "Show Fewer") : String(localized: "Show All (\(items.count))")) {
                        showAll.toggle()
                    }
                    .buttonStyle(.link)
                    .settingsRow()
                }
            }
        }
    }

    private func downloadRow(_ item: XcodeDownloadItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayVersion)
                Text(downloadDetail(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = downloads.errors[item.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if downloads.activeID == item.id {
                ProgressView(value: downloads.progress)
                    .frame(width: 80)
                Text("\(Int(downloads.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    downloads.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel download")
            } else if let file = downloads.finished[item.id] {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            } else {
                Button("Download") { downloads.download(item) }
                    .disabled(downloads.activeID != nil)
            }
        }
        .settingsRow()
    }

    private func downloadDetail(_ item: XcodeDownloadItem) -> String {
        var parts: [String] = []
        if let date = item.date.flatMap({ Calendar(identifier: .gregorian).date(from: $0) }) {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let requires = item.requiresMacOS {
            parts.append(String(localized: "Requires macOS \(requires)"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func refresh() async {
        await session.restore()
        await session.refreshSignedInState()
    }

    private func signIn() async {
        busy = true
        feedback = nil
        defer { busy = false }
        let window = AppleDeveloperSignInWindow()
        let signedIn = await window.present()
        feedback = signedIn ? nil : .cancelled
    }

    private func signOut() async {
        busy = true
        defer { busy = false }
        await session.signOut()
        feedback = .signedOut
    }
}

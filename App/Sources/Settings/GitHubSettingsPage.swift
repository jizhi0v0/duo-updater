import SwiftUI
import AppKit
import DuoUpdaterCore

/// GitHub access: the `gh` CLI status, and a personal access token for when the
/// CLI isn't signed in. The token is verified against GitHub before it's
/// persisted, so a bad paste never silently becomes the saved token.
struct GitHubSettingsPage: View {
    @Bindable var prefs: Preferences

    /// nil while the `gh auth status` probe is in flight.
    @State private var cliStatus: GitHubToken.CLIStatus?
    /// Reveal the token in plain text (eye toggle).
    @State private var revealToken = false

    /// Editable copy of the token. Verified against GitHub and only written into
    /// `prefs.githubToken` once confirmed valid.
    @State private var draft = ""
    /// Result of the last verification of `draft`; nil before any attempt.
    @State private var verification: GitHubToken.Verification?
    @State private var verifying = false
    /// Show the editable field. When false and a token is saved, we show a
    /// compact masked summary instead of a wall of characters.
    @State private var editing = false
    @FocusState private var tokenFocused: Bool

    private static let tokenSettingsURL = URL(string: "https://github.com/settings/tokens")!

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SettingsPage(section: .github) {
            cliCard
            tokenCard
        }
        // Click anywhere outside the field to drop focus. Child controls get the
        // tap first, so buttons/field still work; only empty space resigns.
        .onTapGesture { tokenFocused = false }
        .onAppear { editing = prefs.githubToken.isEmpty }
        .task {
            // Off the main thread: `gh auth status` shells out twice.
            cliStatus = await Task.detached(priority: .userInitiated) {
                GitHubToken.cliStatus()
            }.value
        }
    }

    // MARK: - CLI

    private var cliCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("GitHub CLI integration").fontWeight(.semibold)
                        // One status slot right after the title, fixed size, so
                        // loading → failed → success never shifts the title.
                        SettingsStatusBadge(state: cliBadge)
                            .frame(width: 16, height: 16)
                    }
                    Text(statusHeadline)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .authenticated(let username?) = cliStatus {
                        Text("Signed in as \(username)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .settingsRow()
        }
    }

    private var cliBadge: SettingsStatusBadge.State {
        switch cliStatus {
        case .none:                          return .loading
        case .authenticated:                 return .ok
        case .notInstalled, .notLoggedIn:    return .warning
        }
    }

    private var statusHeadline: String {
        switch cliStatus {
        case .none:          return "Checking the gh CLI…"
        case .authenticated: return "GitHub CLI is authenticated and ready."
        case .notLoggedIn:   return "GitHub CLI is installed but not signed in. Run `gh auth login`, or paste a token below."
        case .notInstalled:  return "GitHub CLI isn’t installed. Paste a personal access token below to lift the rate limit."
        }
    }

    // MARK: - Token

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            // "GitHub token — or paste a personal access token", where the tail
            // opens GitHub's token page. NSWorkspace rather than a markdown link
            // / SwiftUI openURL — the latter errors -50 in this window.
            HStack(spacing: 0) {
                Text("GitHub token — or ")
                Button("create a personal access token") {
                    NSWorkspace.shared.open(Self.tokenSettingsURL)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                if editing {
                    tokenField.settingsRow()
                    SettingsDivider()
                    tokenActionRow.settingsRow()
                } else {
                    savedTokenRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardBackground()

            SettingsFootnote("Lifts the anonymous 60-requests/hour limit to 5000/hour for apps tracked through GitHub Releases. When the gh CLI is signed in this is filled automatically, so the field is optional. A read-only (public-repo) token is enough.")
        }
    }

    @ViewBuilder private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if revealToken {
                    TextField("Paste token", text: $draft)
                } else {
                    SecureField("Paste token", text: $draft)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .textContentType(.password)
            .autocorrectionDisabled()
            .focused($tokenFocused)
            .onSubmit { if !trimmedDraft.isEmpty { Task { await verifyAndSave() } } }
            // A fresh edit invalidates the previous verdict.
            .onChange(of: draft) { verification = nil }

            Button {
                revealToken.toggle()
            } label: {
                Image(systemName: revealToken ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(revealToken ? "Hide token" : "Show token")
        }
    }

    /// Verdict on the left, buttons on the right. Keeping the verdict on this row
    /// (rather than a row that appears/disappears) stops the card growing and
    /// flickering on verify.
    @ViewBuilder private var tokenActionRow: some View {
        HStack(spacing: 10) {
            verificationInline
            Spacer(minLength: 8)
            // Keep the button mounted and show the spinner beside it (rather than
            // swapping button↔spinner), so the row height never jumps.
            ProgressView()
                .controlSize(.small)
                .opacity(verifying ? 1 : 0)
            if !prefs.githubToken.isEmpty {
                Button("Cancel") { editing = false; draft = ""; verification = nil }
                    .disabled(verifying)
            }
            Button("Verify & Save") { Task { await verifyAndSave() } }
                .settingsGlassButton(prominent: true)
                .disabled(trimmedDraft.isEmpty || verifying)
        }
    }

    /// Compact summary once a token is saved: a key glyph, the masked token
    /// (never the full secret), the verified account, and a Change button.
    @ViewBuilder private var savedTokenRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(maskSecret(prefs.githubToken))
                    .font(.system(.body, design: .monospaced))
                Text(prefs.githubTokenAccount.isEmpty
                     ? "Saved"
                     : "Saved · belongs to \(prefs.githubTokenAccount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Change") { startEditing() }
            Button("Remove", role: .destructive) { clearSaved() }
        }
        .settingsRow()
    }

    /// Single-line verdict: who the token belongs to, or why it failed. One line,
    /// truncating, so the row height is stable.
    @ViewBuilder private var verificationInline: some View {
        switch verification {
        case .valid(let username, _):
            Label {
                Text("Valid — belongs to **\(username)**")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.callout)
            .lineLimit(1)
        case .invalid:
            Label("Rejected by GitHub — check it’s correct and not expired.",
                  systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(1)
        case .failed(let message):
            Label("Couldn’t verify: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .lineLimit(1)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Actions

    /// Verify the draft against GitHub; persist only on success, then collapse
    /// back to the masked summary.
    private func verifyAndSave() async {
        verifying = true
        verification = nil
        let result = await GitHubToken.verify(trimmedDraft)
        verifying = false
        verification = result
        if case .valid(let username, _) = result {
            prefs.githubToken = trimmedDraft   // commit only when confirmed
            prefs.githubTokenAccount = username
            draft = ""
            editing = false
        }
    }

    /// Switch to the editable field to replace the saved token.
    private func startEditing() {
        draft = ""
        verification = nil
        editing = true
        tokenFocused = true
    }

    private func clearSaved() {
        draft = ""
        prefs.githubToken = ""
        prefs.githubTokenAccount = ""
        verification = nil
        editing = true
    }
}

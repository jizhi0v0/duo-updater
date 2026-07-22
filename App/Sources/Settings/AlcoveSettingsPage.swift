import SwiftUI
import SystemConfiguration
import DuoUpdaterCore

/// Onboarding for Alcove's licensed (authoritative) update channel. Alcove pushes
/// each build to its licensed API before any public mirror, so precise detection
/// needs the user's license key. From the key alone we recover this Mac's
/// activation `instance_id` (`AlcoveLicenseService`, net-zero activation slots);
/// when the license is at its activation limit we can't, so an advanced field
/// accepts a manually captured id. Without either, Alcove silently falls back to
/// the public (lagging) probe.
struct AlcoveSettingsPage: View {
    @Bindable var prefs: Preferences

    enum SaveStatus: Equatable {
        case idle, resolving
        case ok(consumedSlot: Bool)
        case atLimit(usage: Int, limit: Int)
        case invalid
        case failed(String)
    }

    @State private var draft = ""
    @State private var instanceDraft = ""
    @State private var status: SaveStatus = .idle
    @State private var editing = false
    @State private var revealKey = false
    @State private var showAdvanced = false
    @FocusState private var keyFocused: Bool

    private var trimmedKey: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstance: String { instanceDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var busy: Bool { status == .resolving }

    var body: some View {
        SettingsPage(section: .alcove) {
            SettingsCard(
                header: "Alcove license key",
                footer: "Alcove ships new versions to its licensed update channel before any public download, so precise detection needs your license key (Alcove → Settings → License). It’s stored in the Keychain, never synced off this Mac, and only ever sent to api.tryalcove.com — the same place Alcove sends it. Without it, Alcove still updates via the public feed, just a little later."
            ) {
                if editing { editor } else { savedRow }
            }

            if editing { advancedCard }
        }
        .onTapGesture { keyFocused = false }
        .onAppear { editing = prefs.alcoveLicenseKey.isEmpty }
    }

    // MARK: - Editor

    @ViewBuilder private var editor: some View {
        HStack(spacing: 8) {
            Group {
                if revealKey {
                    TextField("Paste license key", text: $draft)
                } else {
                    SecureField("Paste license key", text: $draft)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .textContentType(.password)
            .autocorrectionDisabled()
            .focused($keyFocused)
            .onSubmit { if !trimmedKey.isEmpty { Task { await resolveAndSave() } } }

            Button { revealKey.toggle() } label: {
                Image(systemName: revealKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(revealKey ? "Hide" : "Reveal")
        }
        .settingsRow()

        SettingsDivider()

        HStack(spacing: 10) {
            statusInline
            Spacer(minLength: 8)
            ProgressView()
                .controlSize(.small)
                .opacity(busy ? 1 : 0)
            Button("Save") { Task { await resolveAndSave() } }
                .settingsGlassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedKey.isEmpty || busy)
        }
        .settingsRow()
    }

    /// Split out of the license card: the instance-ID escape hatch is only for a
    /// license at its activation limit, so it gets its own collapsed card rather
    /// than pushing the common path down.
    private var advancedCard: some View {
        SettingsCard {
            DisclosureGroup("Advanced — set instance ID manually", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Only needed if your license is at its activation limit (then the ID can’t be recovered automatically). Capture this Mac’s instance_id from Alcove’s update request, or free an activation slot in Alcove instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("instance_id (UUID)", text: $instanceDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                    Button("Save key + instance ID") { Task { await saveManual() } }
                        .settingsGlassButton()
                        .disabled(trimmedKey.isEmpty || trimmedInstance.isEmpty || busy)
                }
                .padding(.top, 6)
            }
            .settingsRow()
        }
    }

    @ViewBuilder private var statusInline: some View {
        switch status {
        case .idle, .resolving:
            EmptyView()
        case .ok(let consumed):
            Label(consumed ? "Saved — using a new activation for this Mac."
                           : "Saved — precise detection enabled.",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout).lineLimit(2)
        case .atLimit(let usage, let limit):
            Label("License at activation limit (\(usage)/\(limit)). Key saved — set the instance ID below, or free a slot in Alcove.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout).lineLimit(3)
        case .invalid:
            Label("Alcove rejected this license key.", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.callout).lineLimit(1)
        case .failed(let message):
            Label("Couldn’t reach Alcove: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout).lineLimit(2)
        }
    }

    // MARK: - Saved summary

    @ViewBuilder private var savedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(maskSecret(prefs.alcoveLicenseKey))
                    .font(.system(.body, design: .monospaced))
                Text(prefs.alcoveInstanceID.isEmpty
                     ? "Saved"
                     : "Active · instance …\(prefs.alcoveInstanceID.suffix(4))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Change") { startEditing() }
            Button("Remove", role: .destructive) { clearSaved() }
        }
        .settingsRow()
    }

    // MARK: - Actions

    private func resolveAndSave() async {
        status = .resolving
        let service = AlcoveLicenseService()
        let result = await service.resolveInstanceID(
            licenseKey: trimmedKey, deviceName: Self.computerName(), deviceModel: Self.hardwareModel())
        switch result {
        case .resolved(let id, let consumed):
            prefs.alcoveLicenseKey = trimmedKey
            prefs.alcoveInstanceID = id
            draft = ""; editing = false
            status = .ok(consumedSlot: consumed)
        case .atLimit(let usage, let limit):
            prefs.alcoveLicenseKey = trimmedKey   // key is valid; keep it
            showAdvanced = true
            status = .atLimit(usage: usage, limit: limit)
        case .invalidLicense:
            status = .invalid
        case .failed(let message):
            status = .failed(message)
        }
    }

    /// Save a manually supplied instance id (advanced / at-limit path), after a
    /// read-only license validation.
    private func saveManual() async {
        status = .resolving
        let service = AlcoveLicenseService()
        guard let info = await service.validate(licenseKey: trimmedKey) else {
            status = .failed("validation request failed"); return
        }
        guard info.active else { status = .invalid; return }
        prefs.alcoveLicenseKey = trimmedKey
        prefs.alcoveInstanceID = trimmedInstance
        draft = ""; instanceDraft = ""; editing = false
        status = .ok(consumedSlot: false)
    }

    private func startEditing() {
        draft = ""; instanceDraft = ""; status = .idle; editing = true; keyFocused = true
    }

    private func clearSaved() {
        prefs.alcoveLicenseKey = ""
        prefs.alcoveInstanceID = ""
        draft = ""; instanceDraft = ""; status = .idle; editing = true
    }

    // MARK: - Helpers

    /// This Mac's ComputerName — the name Alcove keys its activation on.
    static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?)
            ?? Host.current().localizedName ?? "Mac"
    }

    /// This Mac's hardware model identifier (e.g. "Mac15,11").
    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}

import SwiftUI
import DuoUpdaterCore

/// The source of a choice is independent of evidence about restart behaviour.
enum AutomaticUpdateCategorySource {
    case userChoice, defaultChoice, suggestion, pendingChoice

    var text: LocalizedStringKey {
        switch self {
        case .userChoice: "Your saved choice"
        case .defaultChoice: "Default setting — you haven’t chosen for this app"
        case .suggestion: "Suggested for this setup — not applied yet"
        case .pendingChoice: "Your choice in this setup — not applied yet"
        }
    }
}

/// A compact explanation first, with technical evidence available on demand.
struct AutomaticUpdateExplanationView: View {
    let appName: String
    let icon: NSImage
    let mode: AutomaticUpdateChoices.Mode
    let source: AutomaticUpdateCategorySource
    let suggestion: AutomaticUpdateSuggestion?
    @Binding var expanded: Bool
    var updateHold: String? = nil

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .frame(height: 500)
        }
        .frame(width: 340)
        .frame(maxHeight: 500)
        .fixedSize(horizontal: false, vertical: true)
        // A popover can inherit its triggering row's selection/bold styling.
        .font(.system(size: 13))
        .fontWeight(.regular)
        .foregroundStyle(.primary)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(appName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(source.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let updateHold {
                Label("Update paused", systemImage: "pause.circle")
                    .font(.callout.weight(.medium))
                Text(updateHold).font(.callout)
            }
            if let suggestion {
                Divider()
                summary(suggestion)
                DisclosureGroup(isExpanded: $expanded) {
                    details(suggestion)
                        .padding(.top, 8)
                } label: {
                    Text("Details")
                        .font(.callout)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func summary(_ suggestion: AutomaticUpdateSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // Missing metadata is not a recommendation. Otherwise show a
            // recommendation only when it adds something to the current mode.
            if suggestion.reasons.contains(.unreadableBundle) {
                Text(Self.reason(.unreadableBundle))
            } else {
                if (suggestion.isSuggested ? AutomaticUpdateChoices.Mode.alsoWhenRunning : .whenClosed) != mode {
                    Text(suggestion.isSuggested
                         ? "Recommendation: Keep Up to Date"
                         : "Recommendation: Only When Not Running")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                if suggestion.observationMatches, let observation = suggestion.observation {
                    Text("Local observation for this version")
                    Text(verbatim: "\(observation.version) (\(observation.build)) · \(observation.observedOn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Restart behavior hasn’t been verified for this setup.")
                }
            }
        }
    }

    private func details(_ suggestion: AutomaticUpdateSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .alsoWhenRunning {
                Text("Allowing restarts does not guarantee uninterrupted work.")
            }
            ForEach(Array(suggestion.reasons.filter {
                $0 != .insufficientEvidence && $0 != .unreadableBundle
            }.enumerated()), id: \.offset) { _, reason in
                Text(Self.reason(reason))
            }
            if let observation = suggestion.observation {
                if !suggestion.observationMatches {
                    Text("Historical observation — not verified for this version or macOS")
                        .fontWeight(.medium)
                }
                Text(verbatim: "\(observation.version) (\(observation.build)) · \(observation.observedOn) · macOS \(observation.macOSVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: observation.summary)
                Text("One observed result does not guarantee every task or future update.")
            }
            Text("For individual update attempts and delays, see Network → Events.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .alsoWhenRunning: "Keep Up to Date"
        case .whenClosed: "Only When Not Running"
        case .never: "Never"
        }
    }

    private static func reason(_ reason: AutomaticUpdateSuggestion.Reason) -> LocalizedStringKey {
        switch reason {
        case .menuBarApp: "Agent app; this does not establish that restarting preserves work."
        case .backgroundOnlyApp: "Background app; restarting may interrupt ongoing work."
        case .automaticTermination: "Supports macOS automatic termination under specific conditions; the app may disable it during work."
        case .suddenTermination: "Supports sudden termination, such as at logout. This does not guarantee task continuity."
        case .networkExtension: "Network extension: updates may affect connections."
        case .fileSync: "File provider extension: updates may affect synchronization."
        case .systemExtension: "System extensions have a separate update lifecycle."
        case .inputMethod: "Restarting this input method may interrupt typing."
        case .insufficientEvidence: "Restart behavior hasn’t been verified for this setup."
        case .unreadableBundle: "App metadata is unavailable; no recommendation can be made."
        }
    }
}

/// The fourth column describes installation limits, not restart recommendations.
struct ManualAutomaticUpdateExplanationButton: View {
    let result: UpdateResult
    let reason: String
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Why this category?")
        .help("Why this category?")
        .popover(isPresented: $showing) {
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }.frame(height: 500)
            }
            .frame(width: 340)
            .frame(maxHeight: 500)
            .fixedSize(horizontal: false, vertical: true)
            .font(.system(size: 13))
            .fontWeight(.regular)
            .foregroundStyle(.primary)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: AppIconCache.icon(for: result.app.path.path))
                    .resizable().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(result.app.name).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Manual Updates").font(.title3.weight(.semibold))
            Text(reason).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let source = result.remote?.sourceName {
                LabeledContent("Source") { Text(verbatim: source) }
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: IgnoredSettingsPage.displayPath(result.app.path.path))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
    }
}

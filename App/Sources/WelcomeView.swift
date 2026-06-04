import SwiftUI
import AppKit
import DuoUpdaterCore

/// First-run onboarding. Surfaces the two macOS permissions Duo Updater needs *before*
/// they block an update mid-flight, so the user grants them deliberately instead of
/// being interrupted by a system prompt the first time they hit Update.
///
/// Styled like the macOS setup assistant: a chromeless, translucent (frosted-glass)
/// window with a hero header and floating glass permission cards. On macOS 26 the cards
/// and primary button use real **Liquid Glass** (`.glassEffect` / `.glassProminent`);
/// earlier systems fall back to `ultraThinMaterial`, so it degrades cleanly.
///
/// The two permissions are asymmetric and the UI reflects that honestly:
///   • **Accessibility** has a status API (`AXIsProcessTrusted()`) — polled while open,
///     so the card flips to "Granted ✓" the instant the user toggles it.
///   • **App Management** has no *public* status API; we read it via the private
///     `TCCAccessPreflight` SPI (`appManagementStatus`). When that SPI is unavailable we
///     fall back to an honest "can't verify — grant to be safe" presentation.
struct WelcomeView: View {
    static let windowID = "welcome"

    @Bindable var model: AppListModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            auroraBackground

            VStack(spacing: 0) {
                hero
                    .padding(.top, 46)
                    .padding(.horizontal, 36)

                cards
                    .padding(.top, 30)
                    .padding(.horizontal, 30)

                Spacer(minLength: 20)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
            }
        }
        .frame(width: 560, height: 600)
        .onAppear {
            model.windowAppeared()
            model.beginTrustPolling()
        }
        .onDisappear {
            model.endTrustPolling()
            model.windowDisappeared()
        }
    }

    /// A self-contained dark "aurora" gradient — like the macOS setup assistant's
    /// backdrop. Crucially it gives the Liquid Glass tiles/button something to refract
    /// (over a flat gray window they'd look invisible), and doesn't depend on whatever
    /// happens to be behind the window.
    private var auroraBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.17, blue: 0.26),
                         Color(red: 0.08, green: 0.09, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // Top-left indigo + right teal blooms — the colour the glass refracts.
            RadialGradient(
                colors: [Color(red: 0.38, green: 0.36, blue: 0.92).opacity(0.55), .clear],
                center: UnitPoint(x: 0.12, y: -0.05), startRadius: 0, endRadius: 480
            )
            RadialGradient(
                colors: [Color(red: 0.20, green: 0.58, blue: 0.66).opacity(0.50), .clear],
                center: UnitPoint(x: 1.02, y: 0.88), startRadius: 0, endRadius: 500
            )
            // A glow directly behind the button so its glass has real brightness to
            // refract — that's what reads as "translucent" rather than a dark pill.
            RadialGradient(
                colors: [Color(red: 0.52, green: 0.32, blue: 0.74).opacity(0.46), .clear],
                center: UnitPoint(x: 0.5, y: 1.10), startRadius: 0, endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

            VStack(spacing: 8) {
                Text("Welcome to Duo Updater")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Two macOS permissions let Duo Updater install updates without interrupting you. You only grant them once — they persist across launches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cards: some View {
        let stack = VStack(spacing: 14) {
            PermissionCard(
                systemImage: "accessibility",
                title: "Accessibility",
                detail: "Lets Duo Updater press App Store’s Update button for silent, incremental (delta) updates — no full re-download, and no separate “mas” tool.",
                status: model.accessibilityTrusted ? .granted : .needed,
                action: { model.presentAccessibilityPermissionFlow() }
            )
            PermissionCard(
                systemImage: "shippingbox",
                title: "App Management",
                detail: appManagementDetail,
                status: appManagementCardStatus,
                action: { model.presentAppManagementPermissionFlow() }
            )
        }
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14) { stack }
        } else {
            stack
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            getStartedButton
            Spacer()
        }
    }

    @ViewBuilder
    private var getStartedButton: some View {
        if #available(macOS 26.0, *) {
            // Explicit *interactive* Liquid Glass on the label (not the subtle `.glass`
            // button style, which all but vanishes over a flat backdrop): a defined glass
            // capsule that brightens/refracts on hover and press.
            Button {
                hasCompletedOnboarding = true
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 13)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        } else {
            Button {
                hasCompletedOnboarding = true
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - App Management status mapping

    /// Map the App Management TCC status onto the card's three visual states. We can
    /// now read it via `TCCAccessPreflight` — so `granted` shows a real check — and
    /// only fall back to the honest "can't verify" presentation when the SPI is absent.
    private var appManagementCardStatus: PermissionCard.Status {
        switch model.appManagementStatus {
        case .granted: return .granted
        case .denied, .notDetermined: return .needed
        case .unknown: return .unverifiable
        }
    }

    private var appManagementDetail: String {
        let base = "Lets Duo Updater replace apps updated outside the App Store (Sparkle, Homebrew, direct downloads)."
        if model.appManagementStatus == .unknown {
            return base + " macOS isn’t reporting its status on this system — grant it to be safe."
        }
        return base
    }
}

// MARK: - Permission card

/// One permission row: icon + explanation on the left, a live status / grant action on
/// the right, on a floating glass tile.
private struct PermissionCard: View {
    enum Status {
        case granted        // verified on (Accessibility, or App Management via SPI)
        case needed         // verified off — actionable
        case unverifiable   // App Management when the status SPI is unavailable
    }

    let systemImage: String
    let title: String
    let detail: String
    let status: Status
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing
                .frame(minWidth: 92, alignment: .trailing)
        }
        .padding(16)
        .modifier(GlassTile())
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(.medium))
        case .needed:
            grantButton(prominent: true)
        case .unverifiable:
            grantButton(prominent: false)
        }
    }

    @ViewBuilder
    private func grantButton(prominent: Bool) -> some View {
        let button = Button("Grant…", action: action)
        if #available(macOS 26.0, *) {
            if prominent { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.glass) }
        } else {
            if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
        }
    }
}

/// A floating glass tile: real Liquid Glass on macOS 26, `ultraThinMaterial` before that.
private struct GlassTile: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.10))
                )
        }
    }
}


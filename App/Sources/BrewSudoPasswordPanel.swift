import AppKit
import SwiftUI
import DuoUpdaterCore

/// Where brew's sudo asks for the administrator password when a cask upgrade
/// runs a pkg (`BrewAskPass`).
///
/// Our own panel, not the system's administrator panel the command-line tools
/// use (`CLIToolAdministratorRun`): that one runs a command as root, and brew
/// refuses to run as root. brew runs as the user and calls sudo itself, which
/// reads the password from the `SUDO_ASKPASS` program; this is that program's
/// other end. The panel says which casks ask, since sudo's own prompt can't.
///
/// Not modal. An `NSAlert.runModal()` entered from a main-queue block keeps the
/// main queue from draining until it returns (`QuitCoordinator`'s measurement),
/// so the whole app would freeze until the panel is answered — the shape #1502
/// took out of the command-line tools' panel ("held the whole app until
/// answered"). This one is a floating panel the caller awaits: the app keeps
/// drawing and counting while it is up, and the run's end or a cancel closes it
/// (task cancellation, which `BrewAskPass` sends when its run is over).
@MainActor
final class BrewSudoPasswordPanel: NSObject, NSWindowDelegate {
    /// What the brew service is handed.
    static let prompt: SudoPasswordPrompt = { request in
        let panel = await MainActor.run { BrewSudoPasswordPanel(request) }
        return await withTaskCancellationHandler {
            await panel.answer()
        } onCancel: {
            Task { @MainActor in panel.finish(nil) }
        }
    }

    /// Panels up, held until answered.
    private static var open: Set<BrewSudoPasswordPanel> = []

    private let request: SudoPasswordRequest
    private var window: NSPanel?
    private var continuation: CheckedContinuation<String?, Never>?
    private var finished = false

    private init(_ request: SudoPasswordRequest) {
        self.request = request
    }

    private func answer() async -> String? {
        await withCheckedContinuation { continuation in
            guard !finished else { return continuation.resume(returning: nil) }
            self.continuation = continuation
            show()
        }
    }

    private func show() {
        Self.open.insert(self)
        let names = ListFormatter.localizedString(byJoining: request.packages)
        let message = request.attempt > 1
            ? String(localized: "That password didn’t work. Enter it again to upgrade \(names).")
            : String(localized: "Upgrading \(names) runs its installer as an administrator. DuoUpdater hands the password to Homebrew’s sudo for this upgrade and doesn’t keep it.")
        let content = BrewSudoPasswordView(
            message: message,
            submit: { [weak self] password in self?.finish(password) },
            cancel: { [weak self] in self?.finish(nil) })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 10),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = String(localized: "Homebrew needs your administrator password")
        panel.contentView = NSHostingView(rootView: content)
        // Above other apps' windows even when macOS declines to activate an
        // accessory app, and not hidden when the person clicks elsewhere.
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        Log.install.notice("brew sudo: asking for \(self.request.packages.joined(separator: " "), privacy: .public) (ask \(self.request.attempt, privacy: .public))")
    }

    /// Once: the answer, or nil for Cancel, the close button, or the run's end.
    func finish(_ password: String?) {
        guard !finished else { return }
        finished = true
        if window != nil {
            Log.install.notice("brew sudo: password \(password == nil ? "declined" : "given", privacy: .public) for \(self.request.packages.joined(separator: " "), privacy: .public)")
        }
        window?.delegate = nil
        window?.close()
        window = nil
        continuation?.resume(returning: password)
        continuation = nil
        Self.open.remove(self)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { finish(nil) }
    }
}

/// The panel's content: what asks, the field, Cancel and Update. Update stays
/// disabled while the field is empty, so a stray Return is not a decline.
private struct BrewSudoPasswordView: View {
    let message: String
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("", text: $password)
                .onSubmit { if !password.isEmpty { submit(password) } }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Update")) { submit(password) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

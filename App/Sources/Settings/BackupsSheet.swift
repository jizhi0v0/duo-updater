import SwiftUI
import AppKit
import DuoUpdaterCore

/// Pick which stored backups to delete.
///
/// "Clean Up Now" used to prune only orphans — backups whose app was uninstalled —
/// which on a machine where every app is still installed deleted nothing, reported
/// nothing, and left the same number on screen. Reading "Backups are using 10 GB"
/// next to a Clean Up button, that is indistinguishable from broken.
///
/// So the button now means what it looks like it means: clear the backups. Every
/// one is a rollback point, though, and reclaiming space costs the ability to undo
/// those updates — which is a decision to put in front of someone rather than
/// behind a single click. Hence a list, with everything selected, and the freed
/// total on the button.
struct BackupsSheet: View {
    let backups: [BackupStore.Listing]
    /// Called with the keys to delete. Empty selection can't reach it — the button
    /// disables — so a stray Return can't wipe anything.
    let onDelete: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String>

    init(backups: [BackupStore.Listing], onDelete: @escaping ([String]) -> Void) {
        self.backups = backups
        self.onDelete = onDelete
        // Everything, because that is what pressing "Clean Up" asks for; unticking
        // is how you keep the rollback points that matter to you.
        _selected = State(initialValue: Set(backups.map(\.key)))
    }

    private var selectedBytes: Int64 {
        backups.filter { selected.contains($0.key) }.reduce(0) { $0 + $1.sizeBytes }
    }

    private var allSelected: Bool { selected.count == backups.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 620, height: 470)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Delete backups").font(.headline)
            Text("Each backup lets one update be rolled back. Deleting it frees the space and gives up that option — the app itself is untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(backups) { backup in
                    row(backup)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func row(_ backup: BackupStore.Listing) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: binding(for: backup))
                .labelsHidden()
            // The icon comes from the backed-up bundle, not the installed app, so it
            // still resolves for something uninstalled — precisely when a name on
            // its own identifies least.
            Image(nsImage: icon(for: backup))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                // Name alone on its line: version strings here run to
                // `5.22.2026072503-alpha`, and sharing a line with one wraps the
                // name mid-word ("HBuilderX-" / "Alpha.app").
                Text(backup.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let version = backup.version {
                        if let current = backup.currentVersion, current != version {
                            // Same grammar as every other version pair in the app
                            // (see `MenuContentView.toVersion`): the older one
                            // recedes, the current one is tinted and semibold.
                            Text(version).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(current)
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        } else {
                            Text(version).foregroundStyle(.secondary)
                        }
                    }
                    if let savedAt = backup.savedAt {
                        Text("· \(savedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)
                    }
                    if !backup.isRestorable {
                        Text("· unusable, its record is missing")
                            .foregroundStyle(.orange)
                    } else if !backup.appStillInstalled {
                        Text("· app no longer installed").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                // Shrink rather than wrap — the same treatment the update rows give
                // these date-shaped versions.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The whole row toggles: aiming for a 14pt checkbox in a list you are about
        // to act on wholesale is needless precision.
        .contentShape(Rectangle())
        .onTapGesture { binding(for: backup).wrappedValue.toggle() }
        .contextMenu {
            if let path = backup.bundlePath {
                // Deliberately kept in a dialog that exists to delete things: the
                // question it answers — "what exactly am I about to lose?" — is one
                // people reasonably ask before confirming.
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([path])
                }
            }
        }
    }

    private func binding(for backup: BackupStore.Listing) -> Binding<Bool> {
        Binding(
            get: { selected.contains(backup.key) },
            set: { isOn in
                if isOn { selected.insert(backup.key) } else { selected.remove(backup.key) }
            })
    }

    private func icon(for backup: BackupStore.Listing) -> NSImage {
        guard let path = backup.bundlePath else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: path.path)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(allSelected ? "Deselect All" : "Select All") {
                selected = allSelected ? [] : Set(backups.map(\.key))
            }
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(selected.isEmpty
                   ? "Delete"
                   : "Delete \(selected.count) (\(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)))") {
                onDelete(Array(selected))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

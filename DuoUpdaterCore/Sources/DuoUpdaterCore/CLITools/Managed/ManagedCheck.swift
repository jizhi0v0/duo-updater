import Foundation

/// The one place a manager's verdict becomes a row: the same state rules for
/// every manager (plans/cli-managers-redesign.md §3.2). An adapter says what
/// it knows (`ManagedVerdict`); nothing here asks a manager anything.
///
/// In order:
/// 1. no installed version, or a blocker → `.unknown`, withheld by the blocker;
/// 2. the vendor would upgrade → `.updateAvailable` with the upgrade command,
///    `latestVersion` = the newest within the request;
/// 3. an exact request held below a newer release → `.pinned`, the unpin
///    command to copy, never offered (the 2026-10-13 rule);
/// 4. installed below the newest known, though the vendor would not move it
///    (a range held at its top with newer beyond, D2; the vendor said no) →
///    `.upToDate`, the unpin command on `manualCommand` for the pane's and
///    `duo`'s "beyond the request" line (not to copy: `commandToCopy` hands
///    nothing out for a current row);
/// 5. installed above the newest → `.ahead`; equal → `.upToDate`;
/// 6. nothing known either way → `.unknown`: withheld by the root's binary
///    when that may not run (the check needed it), else channel unreadable.
///
/// Then two gates that only take the one-click away: the root's binary not
/// runnable (its command is handed out to copy, D5.2), and the manager already
/// moving the item (`.busy`).
public enum ManagedCheck {

    public static func status(
        _ verdict: ManagedVerdict, root: ManagedRoot?, upgrade: CLIToolCommand?, unpin: CLIToolCommand?
    ) -> CLIToolStatus {
        let item = verdict.item
        var state: CLIToolState
        var latest: String?
        var oneClick: CLIToolCommand?
        var withheld: CLIToolWithheld?
        var note: String?
        var manual: CLIToolCommand?

        let installed = item.installed
        let newest = item.latestWithinRequest ?? item.latestOverall
        if installed == nil {
            state = .unknown
            withheld = .versionUnreadable
            note = "the installed version could not be read"
        } else if let blocker = verdict.blocker {
            state = .unknown
            withheld = blocker.withheld
            note = blocker.note
        } else if verdict.vendorWouldUpgrade == true {
            state = .updateAvailable
            latest = newest
            oneClick = upgrade
            if upgrade == nil, let root, root.binary == nil {
                // A check that needs no binary (pipx's, from PyPI) still found
                // the update; the program that would run it is not there.
                withheld = .updaterMissing
                note = "\(item.descriptor.displayName)'s program was not found under \(item.root)"
            } else if upgrade == nil {
                withheld = .unsupportedInstaller
                note = "\(item.descriptor.displayName) documents no command that moves \(item.key)"
            }
        } else if let installed, let overall = item.latestOverall, item.request?.kind == .exact,
                  item.descriptor.versionOrder.isNewer(overall, than: installed) {
            state = .pinned
            latest = overall
            manual = unpin
        } else if let installed, let newest {
            switch item.descriptor.versionOrder.compare(installed, newest) {
            case .orderedAscending:
                // Below the newest known, and the vendor would not move it (or
                // could not say): reported as current, with the gap in the pane.
                state = verdict.vendorWouldUpgrade == nil ? .unknown : .upToDate
                latest = newest
                if verdict.vendorWouldUpgrade == nil {
                    withheld = .unsupportedInstaller
                    note = "not checked: \(item.descriptor.displayName) could not say whether its upgrade would move \(item.key)"
                }
            case .orderedDescending:
                state = .ahead
                latest = newest
            case .orderedSame:
                state = .upToDate
                latest = newest
            }
        } else if verdict.vendorWouldUpgrade == false {
            state = .upToDate
            latest = installed
        } else if let root, !root.runnable {
            // Nothing known, because the check runs the manager's own binary
            // and that one may not run (mise's `outdated`, §4.1): the row
            // says why the binary was not run, not that a channel was down.
            state = .unknown
            if let gate = root.binary?.trust.withheld, let binary = root.binary {
                withheld = gate
                note = "\(binary.path) is \(binary.trust.english), so nothing of it is run"
            } else {
                withheld = .updaterMissing
                note = "\(item.descriptor.displayName)'s program was not found under \(item.root)"
            }
        } else {
            state = .unknown
            withheld = .channelUnreadable
            note = "could not read the release channel"
        }

        // A current row held inside its request with newer beyond it (D2):
        // the command that lifts the request rides along for the pane's and
        // `duo`'s "beyond the request" line.
        if state == .upToDate, manual == nil, let installed, let overall = item.latestOverall,
           item.descriptor.versionOrder.isNewer(overall, than: installed) {
            manual = unpin
        }

        // The binary's trust takes the click away, never the verdict: the
        // command stays to copy, as bub's does today (`CLIToolStatus.commandToCopy`).
        if oneClick != nil {
            if let root, root.runnable {
                // offered
            } else if let gate = root?.binary?.trust.withheld {
                manual = oneClick
                oneClick = nil
                withheld = gate
                note = "\(root?.binary?.path ?? "the binary") is \(root?.binary?.trust.english ?? "not verified"), so nothing of it is run"
            } else {
                manual = oneClick
                oneClick = nil
                withheld = .updaterMissing
                note = "\(item.descriptor.displayName)'s program was not found under \(item.root)"
            }
        }
        if oneClick != nil, let busy = verdict.busy {
            oneClick = nil
            withheld = .busy
            note = busy
        }

        return CLIToolStatus(
            kind: .managed, path: item.installPath, identity: item.identity, installedVersion: installed,
            latestVersion: latest, channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
            manualCommand: manual, name: item.name, releaseNotesKey: releaseNotesKey(item),
            // The root's trust rides on the item, so the wording can tell a
            // quarantined binary from another signer's (`CLIToolWording.reason`).
            detail: .managed(item.with(binaryTrust: root?.binary?.trust)))
    }

    /// One document per (manager, item key): two roots with the same item read
    /// the same notes.
    public static func releaseNotesKey(_ item: ManagedItem) -> String {
        "managed:\(item.manager.rawValue):\(item.key)"
    }

    /// What lies beyond the request when the row is current: `latestOverall`
    /// above the installed version. Nil otherwise. The pane's and `duo`'s
    /// "newer beyond the request" line reads this (D2).
    public static func beyondRequest(_ status: CLIToolStatus) -> String? {
        guard status.state == .upToDate, case .managed(let item) = status.detail,
              let installed = item.installed, let overall = item.latestOverall,
              item.descriptor.versionOrder.isNewer(overall, than: installed) else { return nil }
        return overall
    }
}

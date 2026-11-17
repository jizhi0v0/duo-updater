import SwiftUI

/// The same explanation beside Update All and the automatic-update preference.
struct InstallSpaceNotice: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

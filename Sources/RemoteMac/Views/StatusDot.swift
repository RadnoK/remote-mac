import RemoteMacCore
import SwiftUI

struct StatusDot: View {
    let status: HostStatus
    let l10n: L10n

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status.label(l10n))
    }

    private var color: Color {
        switch status {
        case .online:           .green
        case .screenSharingOff: .orange
        case .offline:          .secondary
        case .notFound:         .red
        case .unknown:          .secondary.opacity(0.5)
        }
    }
}

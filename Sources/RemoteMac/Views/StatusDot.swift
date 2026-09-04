import RemoteMacCore
import SwiftUI

struct StatusDot: View {
    let status: HostStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status.label)
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

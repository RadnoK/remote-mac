import Foundation

public enum ProbeOutcome: Sendable, Equatable {
    /// TCP connect succeeded — Screen Sharing is serving.
    case listening
    /// Connection refused. NWConnection surfaces this as `.waiting`, not
    /// `.failed`, so it must be handled there or every closed port stalls.
    case refused
    /// No state emitted before the external deadline. This is what a sleeping
    /// or unreachable Mac looks like.
    case timedOut
    /// Name resolution failed (NWError -65554).
    case dnsFailure
}

public enum HostStatus: Sendable, Equatable {
    case unknown
    case offline
    case online
    case screenSharingOff
    case notFound

    @MainActor
    public func label(_ l10n: L10n) -> String {
        switch self {
        case .unknown:          l10n(.statusUnknown)
        case .offline:          l10n(.statusOffline)
        case .online:           l10n(.statusOnline)
        case .screenSharingOff: l10n(.statusScreenSharingOff)
        case .notFound:         l10n(.statusNotFound)
        }
    }

    /// An open port proves the service listens; it does not prove that
    /// authentication will succeed. The label is worded accordingly.
    public var isConnectable: Bool {
        self == .online
    }
}

public func resolveStatus(tailscaleOnline: Bool?, probe: ProbeOutcome?) -> HostStatus {
    switch probe {
    case .listening:   return .online
    case .refused:     return .screenSharingOff
    case .dnsFailure:  return .notFound
    case .timedOut:    return .offline
    case nil:
        switch tailscaleOnline {
        case false: return .offline
        // Both `true` (probe still pending) and `nil` (hung CLI) are unknown:
        // we have no evidence about the service yet.
        default:    return .unknown
        }
    }
}

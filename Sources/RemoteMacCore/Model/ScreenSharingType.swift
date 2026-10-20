import Foundation

/// How the user wants Screen Sharing's Standard / High Performance chooser
/// answered for a host. Persisted by raw value in `AppSettings`.
public enum ScreenSharingTypePreference: String, Codable, CaseIterable, Sendable {
    /// High Performance on the same LAN, Standard everywhere else.
    case auto
    case standard
    case highPerformance
    /// Leave the chooser alone and let the user pick.
    case ask
}

/// A concrete answer to the chooser.
public enum ScreenSharingType: Sendable, Equatable {
    case standard
    case highPerformance
}

/// Turns a preference into the chooser answer, or `nil` when the chooser
/// should be left for the user (`.ask`).
public func resolveScreenSharingType(
    preference: ScreenSharingTypePreference,
    isOnLocalNetwork: Bool
) -> ScreenSharingType? {
    switch preference {
    case .auto: isOnLocalNetwork ? .highPerformance : .standard
    case .standard: .standard
    case .highPerformance: .highPerformance
    case .ask: nil
    }
}

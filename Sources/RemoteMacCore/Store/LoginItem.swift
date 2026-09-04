import Foundation
import ServiceManagement

public enum LoginItemState: Sendable, Equatable {
    case enabled
    case disabled
    /// The user revoked consent in System Settings. Distinct from `.disabled`,
    /// because the remedy is a trip to System Settings rather than a toggle.
    case requiresApproval
    /// Not running from a signed .app bundle, e.g. under `swift test`.
    case unavailable

    public static let allValues: [LoginItemState] =
        [.enabled, .disabled, .requiresApproval, .unavailable]

    public var label: String {
        switch self {
        case .enabled:          "Włączone"
        case .disabled:         "Wyłączone"
        case .requiresApproval: "Wymaga zgody w Ustawieniach systemowych"
        case .unavailable:      "Niedostępne (aplikacja nie jest podpisana)"
        }
    }
}

/// Wraps `SMAppService.mainApp`. Registration requires a code-signed bundle —
/// unsigned builds fail with `kSMErrorInvalidSignature`.
public enum LoginItem {
    public static var current: LoginItemState {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled:          return .enabled
        case .notRegistered:    return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound:         return .unavailable
        @unknown default:       return .unavailable
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

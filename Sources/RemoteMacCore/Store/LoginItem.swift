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

    @MainActor
    public func label(_ l10n: L10n) -> String {
        switch self {
        case .enabled:          l10n(.loginItemEnabled)
        case .disabled:         l10n(.loginItemDisabled)
        case .requiresApproval: l10n(.loginItemRequiresApproval)
        case .unavailable:      l10n(.loginItemUnavailable)
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
        // `.notFound` means the system has no record of this service yet —
        // the ordinary state for an app that has never registered one. It is
        // NOT evidence that the bundle is unsigned, and reporting it as
        // "unavailable (app is not signed)" was simply false for this signed
        // build: it greyed out a toggle that works. Treat it as "off"; a real
        // signing problem surfaces as a thrown `kSMErrorInvalidSignature`
        // from `register()`, which the settings pane already reports.
        case .notFound:         return .disabled
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

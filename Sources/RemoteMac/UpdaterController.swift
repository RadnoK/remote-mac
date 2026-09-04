import Foundation
import Observation
import Sparkle

/// Wraps Sparkle for the settings UI.
///
/// Sparkle owns the preferences (automatic checks, interval) in UserDefaults —
/// we deliberately do not mirror them in `AppSettings`, to avoid two sources
/// of truth drifting apart.
///
/// Ported from RouterMenu's `UpdaterController`.
@MainActor
@Observable
public final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    /// Bumped after a settings change so the view recomputes properties
    /// read directly from Sparkle.
    private var revision = 0

    public init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private var updater: SPUUpdater { controller.updater }

    public var automaticallyChecksForUpdates: Bool {
        get {
            _ = revision
            return updater.automaticallyChecksForUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = newValue
            revision += 1
        }
    }

    public var automaticallyDownloadsUpdates: Bool {
        get {
            _ = revision
            return updater.automaticallyDownloadsUpdates
        }
        set {
            updater.automaticallyDownloadsUpdates = newValue
            revision += 1
        }
    }

    /// Check interval in seconds; Sparkle enforces a minimum of 1 hour.
    public var updateCheckInterval: TimeInterval {
        get {
            _ = revision
            return updater.updateCheckInterval
        }
        set {
            updater.updateCheckInterval = newValue
            revision += 1
        }
    }

    public var lastUpdateCheckDate: Date? {
        _ = revision
        return updater.lastUpdateCheckDate
    }

    public var canCheckForUpdates: Bool {
        _ = revision
        return updater.canCheckForUpdates
    }

    /// Manual check — shows Sparkle's UI even when there is no new version.
    public func checkForUpdates() {
        updater.checkForUpdates()
        revision += 1
    }
}

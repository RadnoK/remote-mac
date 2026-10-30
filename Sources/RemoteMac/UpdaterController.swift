import Foundation
import Observation
import RemoteMacCore
import Sparkle

/// Wraps Sparkle for the settings UI.
///
/// Sparkle owns the preferences (automatic checks, interval) in UserDefaults —
/// we deliberately do not mirror them in `AppSettings`, to avoid two sources
/// of truth drifting apart.
///
/// The update channel sits in the same UserDefaults, and this class is
/// Sparkle's delegate so it can answer `feedURLString(for:)` with the
/// channel's appcast — a switch takes effect on the next check, no relaunch.
///
/// Ported from RouterMenu's `UpdaterController`.
@MainActor
@Observable
public final class UpdaterController: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private let defaults: UserDefaults

    /// Bumped after a settings change so the view recomputes properties
    /// read directly from Sparkle.
    private var revision = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
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

    /// The release stream this install follows. Switching checks straight
    /// away, so the user sees the effect instead of waiting for the schedule.
    public var channel: UpdateChannel {
        get {
            _ = revision
            return UpdateChannel(storedValue: defaults.string(forKey: UpdateChannel.defaultsKey))
        }
        set {
            guard newValue != channel else { return }
            defaults.set(newValue.rawValue, forKey: UpdateChannel.defaultsKey)
            revision += 1
            checkForUpdates()
        }
    }

    /// Sparkle's delegate protocol is main-actor, so reading defaults here
    /// is safe.
    public func feedURLString(for updater: SPUUpdater) -> String? {
        channel.appcastURL.absoluteString
    }

    /// Manual check — shows Sparkle's UI even when there is no new version.
    public func checkForUpdates() {
        updater.checkForUpdates()
        revision += 1
    }
}

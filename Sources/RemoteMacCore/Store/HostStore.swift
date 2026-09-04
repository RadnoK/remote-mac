import Foundation
import Observation

public struct HostEntry: Sendable, Identifiable, Equatable {
    public let host: Host
    public let status: HostStatus
    public var id: String { host.id }

    public init(host: Host, status: HostStatus) {
        self.host = host
        self.status = status
    }
}

@MainActor
@Observable
public final class HostStore {
    public private(set) var entries: [HostEntry] = []
    public private(set) var tailscaleError: String?
    /// User-facing message for a launch (SSH/terminal) that could not be
    /// carried out — e.g. a denied AppleEvents/Automation TCC grant for
    /// Terminal.app. Without this channel, `Launching.execute` failing was
    /// silent: the user would click "SSH" and nothing would happen, with no
    /// dialog, message, or log to explain why.
    public private(set) var launchError: String?
    /// User-facing message for a failed settings write. Persistence used to
    /// swallow the error with `try?`, so a save failure (e.g. an unwritable
    /// path or a full disk) would silently discard the user's edit with no
    /// feedback at all.
    public private(set) var settingsError: String?
    public var settings: AppSettings {
        didSet {
            do {
                try settingsStore.save(settings)
                settingsError = nil
            } catch {
                settingsError = "Nie udało się zapisać ustawień."
            }
        }
    }

    private let tailscale: TailscaleClient
    private let probe: PortProbing
    private let settingsStore: SettingsStore
    private var pollingTask: Task<Void, Never>?
    /// Bumped at the start of every `refresh()` call. Only the call that
    /// still holds the newest generation when it finishes is allowed to
    /// commit `entries` — this lets polling (every 30s) and a menu-open
    /// refresh overlap without a slow, stale call clobbering a faster,
    /// fresher one that started later and already won.
    private var refreshGeneration = 0

    public var isPolling: Bool { pollingTask != nil }
    /// `Launching` implementations may be main-thread-affine (see the doc
    /// comment on `AppKitLauncher`): their `Sendable` conformance only
    /// permits crossing actor boundaries, it does not certify the underlying
    /// AppKit calls are safe off the main thread. `HostStore` is itself
    /// `@MainActor`, so every call into `launcher` below is guaranteed to run
    /// on the main actor — that isolation, not the conformance, is what makes
    /// this safe.
    private let launcher: Launching

    public init(
        tailscale: TailscaleClient = TailscaleClient(),
        probe: PortProbing = NetworkPortProbe(),
        settingsStore: SettingsStore = SettingsStore(),
        launcher: Launching = AppKitLauncher()
    ) {
        self.tailscale = tailscale
        self.probe = probe
        self.settingsStore = settingsStore
        self.launcher = launcher
        self.settings = settingsStore.load()
    }

    /// Refreshes host status. Safe to call while another refresh is already
    /// in flight (e.g. background polling overlapping a menu-open refresh):
    /// every call runs its probes to completion, but only the call that
    /// started *last* is allowed to commit its results to `entries` and the
    /// error banners. This avoids two failure modes a naive "last write
    /// wins at the end" implementation has — a slow call finishing after a
    /// newer, faster one and clobbering fresh data with stale data — while
    /// still letting a menu-open refresh do real work instead of silently
    /// no-oping when a poll tick happens to be in flight.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration

        var discovered: [Host] = []
        var newTailscaleError: String?
        do {
            discovered = try await tailscale.fetchMacs()
        } catch {
            newTailscaleError = message(for: error)
        }

        let hosts = mergeHosts(tailscale: discovered, settings: settings)

        // Each host probes independently so a single sleeping Mac cannot
        // block the menu.
        let probe = self.probe
        let statuses = await withTaskGroup(of: (String, ProbeOutcome).self) { group in
            for host in hosts {
                group.addTask {
                    let outcome = await probe.probe(
                        host: host.ipv4, port: screenSharingPort, timeout: .seconds(2))
                    return (host.id, outcome)
                }
            }
            var results: [String: ProbeOutcome] = [:]
            for await (id, outcome) in group { results[id] = outcome }
            return results
        }

        let newEntries = hosts.map { host in
            HostEntry(
                host: host,
                status: resolveStatus(
                    tailscaleOnline: host.source == .tailscale ? host.isOnline : nil,
                    probe: statuses[host.id]
                )
            )
        }

        // A newer refresh has since started; let its result win instead.
        guard generation == refreshGeneration else { return }
        tailscaleError = newTailscaleError
        entries = newEntries
    }

    /// Refreshes in the background while the menu is closed. Starting twice is
    /// a no-op rather than stacking tasks.
    public func startPolling(interval: Duration = .seconds(30)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func connect(to host: Host) {
        launcher.openScreenSharing(host: host)
    }

    public func openSSH(to host: Host) {
        let terminal = settings.terminal
        let plan = launchPlan(
            for: terminal,
            user: settings.sshUsername(for: host),
            host: host.ipv4,
            isRunning: launcher.isRunning(bundleIdentifier: terminal.bundleIdentifier)
        )
        let succeeded = launcher.execute(plan)
        launchError = succeeded ? nil : launchErrorMessage(for: terminal)
    }

    public func openFiles(for host: Host) {
        launcher.openFileSharing(host: host)
    }

    /// Dismisses the current launch-failure banner. Without this, a single
    /// denied Automation prompt would leave the orange warning showing on
    /// every menu open forever, since it otherwise only clears on the next
    /// `openSSH` call.
    public func clearLaunchError() {
        launchError = nil
    }

    /// Lets a view report (or clear, by passing `nil`) a settings-related
    /// failure that did not originate from the `settings` `didSet` itself —
    /// e.g. `LoginItem.setEnabled` throwing `kSMErrorInvalidSignature`. Reuses
    /// the same `settingsError` channel/banner rather than adding a second,
    /// so the settings window has one place to look for "your last edit here
    /// didn't stick."
    public func reportSettingsError(_ message: String?) {
        settingsError = message
    }

    public func copyAddress(of host: Host) {
        launcher.copyToClipboard(host.ipv4)
    }

    public func availableTerminals() -> [TerminalKind] {
        installedTerminals(using: launcher)
    }

    private func launchErrorMessage(for terminal: TerminalKind) -> String {
        if terminal.requiresAppleEvents {
            return "Nie udało się uruchomić \(terminal.displayName). "
                + "Sprawdź uprawnienia automatyzacji w Ustawieniach systemowych "
                + "→ Prywatność i bezpieczeństwo → Automatyzacja."
        }
        return "Nie udało się uruchomić \(terminal.displayName)."
    }

    private func message(for error: Error) -> String {
        switch error {
        case CommandError.notFound:
            "Nie znaleziono Tailscale."
        case CommandError.timedOut:
            "Tailscale nie odpowiada."
        case TailscaleParseError.guiLaunchFailure:
            "Tailscale nie odpowiada (tryb CLI niedostępny)."
        case let TailscaleParseError.notRunning(state):
            "Tailscale rozłączony (\(state))."
        default:
            "Nie udało się odczytać listy maszyn."
        }
    }
}

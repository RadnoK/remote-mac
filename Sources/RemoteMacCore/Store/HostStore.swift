import Foundation
import Observation

public struct HostEntry: Sendable, Identifiable, Equatable {
    public let host: Host
    public let status: HostStatus
    public let details: HostDetails?
    public var id: String { host.id }

    public init(host: Host, status: HostStatus, details: HostDetails? = nil) {
        self.host = host
        self.status = status
        self.details = details
    }
}

/// Builds the single-line subtitle shown under a host's display name.
///
/// Enrichment only ever runs for `.online` hosts, so once `details` are
/// present the status label is always "Screen Sharing nasłuchuje" — the
/// longest label, and one that carries no new information at that point
/// (the status dot already shows it). With a 1-line limit in a narrow menu
/// row, keeping it would push out the lock indicator, which is the entire
/// point of enrichment. So: no details → IP + status; details present → IP +
/// console user (if any) + lock indicator (if locked), status dropped.
public func hostSubtitle(for entry: HostEntry) -> String {
    guard let details = entry.details else {
        return [entry.host.ipv4, entry.status.label].joined(separator: " · ")
    }
    var parts = [entry.host.ipv4]
    if let user = details.consoleUser { parts.append(user) }
    if details.isScreenLocked == true { parts.append("zablokowany") }
    return parts.joined(separator: " · ")
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
    private let sshStatus: SSHStatusClient
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
        sshStatus: SSHStatusClient = SSHStatusClient(),
        settingsStore: SettingsStore = SettingsStore(),
        launcher: Launching = AppKitLauncher()
    ) {
        self.tailscale = tailscale
        self.probe = probe
        self.sshStatus = sshStatus
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

        // Snapshot the previous entries' details before building `newEntries`
        // so enrichment that fails this tick — for one host or all of
        // them — leaves last-known details in place instead of visibly
        // blanking the subtitle out and back in on every poll.
        let previousDetails = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.details.map { (entry.host.id, $0) }
            }
        )

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
                ),
                details: previousDetails[host.id]
            )
        }

        // A newer refresh has since started; let its result win instead.
        guard generation == refreshGeneration else { return }
        tailscaleError = newTailscaleError
        entries = newEntries

        // Enrichment runs after the list is already visible, so a slow or
        // unavailable SSH path never delays the menu.
        let reachable = entries.filter { $0.status.isConnectable }.map(\.host)
        guard !reachable.isEmpty else { return }

        let sshStatus = self.sshStatus
        let details = await withTaskGroup(of: (String, HostDetails?).self) { group in
            for host in reachable {
                group.addTask { (host.id, await sshStatus.fetchDetails(host: host)) }
            }
            var results: [String: HostDetails] = [:]
            for await (id, detail) in group {
                if let detail { results[id] = detail }
            }
            return results
        }

        // A newer refresh may have started (and possibly already committed)
        // while enrichment awaited SSH round-trips. Re-check the generation
        // before touching `entries` again — otherwise a stale enrichment
        // pass could overwrite a newer refresh's freshly committed entries.
        guard generation == refreshGeneration else { return }
        entries = entries.map { entry in
            HostEntry(host: entry.host, status: entry.status, details: details[entry.host.id] ?? entry.details)
        }
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
            "Nie znaleziono Tailscale. Zainstaluj Tailscale i upewnij się, że jest uruchomiony."
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

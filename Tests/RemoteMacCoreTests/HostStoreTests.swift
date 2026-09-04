import Foundation
import Testing
@testable import RemoteMacCore

private struct StubRunner: CommandRunning {
    let json: String
    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        Data(json.utf8)
    }
}

private struct FailingRunner: CommandRunning {
    let error: CommandError
    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        throw error
    }
}

private struct StubProbe: PortProbing {
    let outcomes: [String: ProbeOutcome]
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        outcomes[host] ?? .timedOut
    }
}

private struct SlowProbe: PortProbing {
    let outcomes: [String: ProbeOutcome]
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        if outcomes[host] == nil { try? await Task.sleep(for: .milliseconds(400)) }
        return outcomes[host] ?? .timedOut
    }
}

private struct NoopLauncher: Launching {
    func openScreenSharing(host: RemoteMacCore.Host) {}
    func openFileSharing(host: RemoteMacCore.Host) {}
    func copyToClipboard(_ text: String) {}
    func execute(_ plan: LaunchPlan) -> Bool { true }
    func isRunning(bundleIdentifier: String) -> Bool { false }
    func isInstalled(bundleIdentifier: String) -> Bool { true }
}

private struct FailingLauncher: Launching {
    func openScreenSharing(host: RemoteMacCore.Host) {}
    func openFileSharing(host: RemoteMacCore.Host) {}
    func copyToClipboard(_ text: String) {}
    func execute(_ plan: LaunchPlan) -> Bool { false }
    func isRunning(bundleIdentifier: String) -> Bool { false }
    func isInstalled(bundleIdentifier: String) -> Bool { true }
}

private let twoMacsJSON = """
{"BackendState":"Running",
 "Self":{"PublicKey":"nodekey:aaa","HostName":"Mini","DNSName":"mini.ts.net.",
         "OS":"macOS","TailscaleIPs":["100.123.34.96"],"Online":true},
 "Peer":{"nodekey:bbb":{"PublicKey":"nodekey:bbb","HostName":"MBP",
         "DNSName":"mbp.ts.net.","OS":"macOS","TailscaleIPs":["100.108.216.101"],
         "Online":true}}}
"""

private let oneMacJSON = """
{"BackendState":"Running",
 "Self":{"PublicKey":"nodekey:aaa","HostName":"Mini","DNSName":"mini.ts.net.",
         "OS":"macOS","TailscaleIPs":["100.123.34.96"],"Online":true}}
"""

/// Returns `oneMacJSON` for the first call and `twoMacsJSON` for every call
/// after that, so a test can tell an "older" refresh's result apart from a
/// "newer" one's. An `actor` (rather than a class with a lock) keeps this
/// safely `Sendable` for `CommandRunning` under strict concurrency.
private actor CountingRunner: CommandRunning {
    private(set) var callCount = 0

    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        callCount += 1
        return Data((callCount == 1 ? oneMacJSON : twoMacsJSON).utf8)
    }
}

/// Blocks only the *first* probe call it receives (identified by call order,
/// not by host) until the test explicitly releases it; every subsequent call
/// returns immediately. This lets a test start an "older" refresh (which
/// blocks on its one probe call), then start and fully complete a "newer"
/// refresh (whose probe calls arrive later and are not blocked), and only
/// afterwards release the older call — deterministically forcing it to
/// finish last.
private actor FirstCallGatedProbe: PortProbing {
    private var callCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        callCount += 1
        if callCount == 1 { await waitForRelease() }
        return .listening
    }

    private func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = waiters
        waiters = []
        for continuation in pending { continuation.resume() }
    }
}

/// Counts calls so a test can prove polling actually stopped producing
/// refreshes, not merely that `isPolling` flipped to `false`.
private actor CountingProbe: PortProbing {
    private(set) var callCount = 0

    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        callCount += 1
        return .listening
    }
}

@MainActor
private func makeStore(
    runner: CommandRunning,
    probe: PortProbing,
    sshStatus: SSHStatusClient = SSHStatusClient(runner: FailingRunner(error: .timedOut)),
    launcher: Launching = NoopLauncher()
) -> HostStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("remotemac-store-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")
    return HostStore(
        tailscale: TailscaleClient(runner: runner, executablePath: "/fake/Tailscale"),
        probe: probe,
        sshStatus: sshStatus,
        settingsStore: SettingsStore(fileURL: url),
        launcher: launcher
    )
}

@MainActor
@Test func refreshPopulatesEntriesWithResolvedStatus() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [
            "100.123.34.96": .listening,
            "100.108.216.101": .refused,
        ])
    )
    await store.refresh()

    #expect(store.entries.count == 2)
    let mini = store.entries.first { $0.host.name == "mini" }
    let mbp = store.entries.first { $0.host.name == "mbp" }
    #expect(mini?.status == .online)
    #expect(mbp?.status == .screenSharingOff)
    #expect(store.tailscaleError == nil)
}

@MainActor
@Test func tailscaleFailureSurfacesMessageAndKeepsManualHosts() async {
    let store = makeStore(
        runner: FailingRunner(error: .timedOut),
        probe: StubProbe(outcomes: ["192.168.1.50": .listening])
    )
    store.settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]
    await store.refresh()

    #expect(store.tailscaleError != nil)
    #expect(store.entries.map(\.host.name) == ["biuro"])
    #expect(store.entries[0].status == .online)
}

@MainActor
@Test func hungTailscaleShowsUnknownNotOffline() async {
    let store = makeStore(
        runner: FailingRunner(error: .timedOut),
        probe: StubProbe(outcomes: [:])
    )
    await store.refresh()
    #expect(store.tailscaleError != nil)
    // No hosts is a distinct condition from "all hosts offline".
    #expect(store.entries.isEmpty)
}

@MainActor
@Test func oneSlowHostDoesNotBlockTheOthers() async {
    // Probes run concurrently, so total time tracks the slowest single probe,
    // not their sum.
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: SlowProbe(outcomes: ["100.123.34.96": .listening])
    )
    let clock = ContinuousClock()
    let start = clock.now
    await store.refresh()
    let elapsed = clock.now - start

    #expect(store.entries.count == 2)
    #expect(elapsed < .milliseconds(900))
}

@MainActor
@Test func hiddenHostsDoNotAppear() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    store.settings.hiddenHostIDs = ["nodekey:aaa"]
    await store.refresh()
    #expect(store.entries.map(\.host.name) == ["mbp"])
}

@MainActor
@Test func entriesAreSortedByDisplayName() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    await store.refresh()
    #expect(store.entries.map(\.host.displayName) == store.entries.map(\.host.displayName).sorted())
}

@MainActor
@Test func failingLauncherSetsLaunchError() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:]),
        launcher: FailingLauncher()
    )
    await store.refresh()
    #expect(store.launchError == nil)

    guard let host = store.entries.first?.host else {
        Issue.record("expected at least one host")
        return
    }
    store.openSSH(to: host)
    #expect(store.launchError != nil)
}

@MainActor
@Test func clearLaunchErrorDismissesTheBanner() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:]),
        launcher: FailingLauncher()
    )
    await store.refresh()

    guard let host = store.entries.first?.host else {
        Issue.record("expected at least one host")
        return
    }
    store.openSSH(to: host)
    #expect(store.launchError != nil)

    store.clearLaunchError()
    #expect(store.launchError == nil)
}

@MainActor
@Test func unwritableSettingsPathSetsSettingsError() async {
    // `/dev/null` is not a directory, so `createDirectory` under it always
    // fails — this simulates a save failure without touching real disk state.
    let unwritableURL = URL(fileURLWithPath: "/dev/null/settings.json")
    let store = HostStore(
        tailscale: TailscaleClient(runner: StubRunner(json: twoMacsJSON), executablePath: "/fake/Tailscale"),
        probe: StubProbe(outcomes: [:]),
        settingsStore: SettingsStore(fileURL: unwritableURL),
        launcher: NoopLauncher()
    )
    #expect(store.settingsError == nil)

    store.settings.defaultSSHUsername = "someone-else"

    #expect(store.settingsError != nil)
}

@MainActor
@Test func settingsErrorClearsOnSubsequentSuccessfulSave() async {
    // The clear-on-success branch in the `settings` `didSet` needs its own
    // assertion: an implementation that set `settingsError` once and never
    // cleared it would still pass `unwritableSettingsPathSetsSettingsError`.
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("remotemac-store-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")
    let store = HostStore(
        tailscale: TailscaleClient(runner: StubRunner(json: twoMacsJSON), executablePath: "/fake/Tailscale"),
        probe: StubProbe(outcomes: [:]),
        settingsStore: SettingsStore(fileURL: url),
        launcher: NoopLauncher()
    )
    #expect(store.settingsError == nil)

    store.settings.defaultSSHUsername = "someone-else"

    #expect(store.settingsError == nil)

    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@MainActor
@Test func reportSettingsErrorSetsAndClearsTheChannel() async {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    #expect(store.settingsError == nil)

    store.reportSettingsError("Nie udało się zmienić ustawienia uruchamiania przy logowaniu.")
    #expect(store.settingsError != nil)

    store.reportSettingsError(nil)
    #expect(store.settingsError == nil)
}

@MainActor
@Test func pollingRefreshesRepeatedly() async throws {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: ["100.123.34.96": .listening])
    )
    store.startPolling(interval: .milliseconds(120))
    defer { store.stopPolling() }

    try await Task.sleep(for: .milliseconds(400))
    #expect(store.entries.count == 2)
}

@MainActor
@Test func stopPollingHaltsFurtherRefreshes() async throws {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    store.startPolling(interval: .milliseconds(100))
    try await Task.sleep(for: .milliseconds(250))
    store.stopPolling()

    #expect(!store.isPolling)
}

@MainActor
@Test func startPollingTwiceDoesNotStackTasks() async throws {
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [:])
    )
    store.startPolling(interval: .milliseconds(100))
    store.startPolling(interval: .milliseconds(100))
    defer { store.stopPolling() }

    #expect(store.isPolling)
}

/// The brief's `stopPollingHaltsFurtherRefreshes` only asserts `isPolling ==
/// false`, which a `stopPolling()` that flipped the flag but left the loop
/// running would still pass — `pollingTask?.cancel(); pollingTask = nil`
/// looks right but the underlying `Task` body only checks `Task.isCancelled`
/// once per iteration, so a bug there (e.g. checking a copy, or the cancel
/// not propagating) would not be caught. This test instead counts actual
/// probe calls: it lets several poll ticks land, stops polling, then waits
/// long enough that another tick *would* have landed if the loop were still
/// alive, and asserts no further call occurred.
@MainActor
@Test func stopPollingActuallyStopsTheBackgroundLoop() async throws {
    let probe = CountingProbe()
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: probe
    )
    store.startPolling(interval: .milliseconds(60))
    try await Task.sleep(for: .milliseconds(200))
    store.stopPolling()

    let countAtStop = await probe.callCount
    #expect(countAtStop > 0)

    try await Task.sleep(for: .milliseconds(300))
    let countAfterWaiting = await probe.callCount

    #expect(countAfterWaiting == countAtStop)
}

/// Pins the re-entrancy ruling from the task brief: once polling can overlap
/// a menu-triggered refresh, a slow *older* refresh must not clobber a fast
/// *newer* one's results. `HostStore` uses a generation counter — every
/// `refresh()` call still runs to completion, but only the call that was
/// still the newest when it started is allowed to commit to `entries`.
///
/// The older call is held open on a gate until after the newer call has
/// already committed two hosts; releasing it and letting it finish last must
/// not regress `entries` back to the older call's one-host result.
@MainActor
@Test func overlappingRefreshesDoNotLetAnOlderCallOverwriteANewerOne() async throws {
    let runner = CountingRunner()
    let gatedProbe = FirstCallGatedProbe()
    let store = makeStore(runner: runner, probe: gatedProbe)

    // Older call: resolves to `oneMacJSON` (1 host, 1 probe call), and that
    // one probe call is the gate's first call, so it blocks mid-refresh
    // before it can commit.
    let olderRefresh = Task { await store.refresh() }
    try await Task.sleep(for: .milliseconds(50))

    // Newer call: resolves to `twoMacsJSON` (2 hosts). Its probe calls are
    // the gate's 2nd/3rd calls, which are not blocked, so this call runs to
    // completion and commits 2 entries while the older call is still
    // parked.
    await store.refresh()
    #expect(store.entries.count == 2)

    // Only now let the older, stale call finish. Because it started before
    // the newer call, its generation is stale by the time it reaches the
    // commit check, so it must not overwrite the newer call's 2 entries.
    await gatedProbe.release()
    await olderRefresh.value

    #expect(store.entries.count == 2)
}

/// Gates the *first* `run` call it receives until explicitly released.
/// Returns a distinct payload per call order (`"stale-user\nNo\n"` for the
/// first call, `"fresh-user\nNo\n"` for every call after), so a test can
/// tell an older refresh's enrichment result apart from a newer one's — the
/// same trick `CountingRunner` uses for the Tailscale fetch, applied to the
/// SSH enrichment call instead. Used to hold an older refresh's SSH
/// enrichment open past the point where a newer refresh has already
/// committed its own entries and enrichment, so releasing it last proves a
/// stale enrichment pass cannot clobber fresher data.
private actor FirstCallGatedSSHRunner: CommandRunning {
    private var callCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        callCount += 1
        let isFirstCall = callCount == 1
        if isFirstCall { await waitForRelease() }
        return Data((isFirstCall ? "stale-user\nNo\n" : "fresh-user\nNo\n").utf8)
    }

    private func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = waiters
        waiters = []
        for continuation in pending { continuation.resume() }
    }
}

/// Pins the same re-entrancy ruling as
/// `overlappingRefreshesDoNotLetAnOlderCallOverwriteANewerOne`, but for the
/// enrichment step specifically: `refresh()` commits `entries` once before
/// awaiting SSH enrichment, then commits again after enrichment completes —
/// that second commit must also respect the generation counter. Without the
/// re-check, a slow *older* refresh's enrichment (started before a newer
/// refresh, but finishing after it) would silently overwrite the newer
/// refresh's already-committed `details`.
@MainActor
@Test func staleEnrichmentPassCannotOverwriteANewerRefreshsEntries() async throws {
    let sshRunner = FirstCallGatedSSHRunner()
    let sshStatus = SSHStatusClient(runner: sshRunner)
    let store = makeStore(
        runner: StubRunner(json: oneMacJSON),
        probe: StubProbe(outcomes: ["100.123.34.96": .listening]),
        sshStatus: sshStatus
    )

    // Older refresh: one reachable host, so its enrichment issues the SSH
    // runner's first call, which the gate blocks before it can return
    // "stale-user" and let the refresh reach its final commit.
    let olderRefresh = Task { await store.refresh() }
    try await Task.sleep(for: .milliseconds(50))

    // Newer refresh: also resolves one reachable host, but its SSH call is
    // the gate's *second* call, which is not blocked and returns
    // "fresh-user" immediately — so this refresh, including enrichment,
    // runs to completion and commits "fresh-user" while the older call is
    // still parked.
    await store.refresh()
    #expect(store.entries.first?.details?.consoleUser == "fresh-user")

    // Only now let the older, stale enrichment call finish with
    // "stale-user". Because it started before the newer call, its
    // generation is stale by the time it reaches the final commit check, so
    // it must not overwrite the newer call's already-committed "fresh-user".
    await sshRunner.release()
    await olderRefresh.value

    #expect(store.entries.count == 1)
    #expect(store.entries.first?.details?.consoleUser == "fresh-user")
}

/// Fakes the SSH runner so a test can make enrichment succeed for a host on
/// the first `refresh()` and fail on the second, independently per host. The
/// SSH arguments always include `"user@<ipv4>"` as the last-but-one element
/// (see `SSHStatusClient.fetchDetails`), so matching on that substring tells
/// which host a given call is for; a per-host call counter then decides
/// whether that call is the "first" (succeeds) or "second" (fails, by
/// returning empty data so `fetchDetails` yields nil) attempt for it.
private actor PerHostSSHRunner: CommandRunning {
    private var callCounts: [String: Int] = [:]
    /// Host IPv4 substrings that should fail (return nil details) starting
    /// on their 2nd call.
    private let failFromSecondCall: Set<String>

    init(failFromSecondCall: Set<String>) {
        self.failFromSecondCall = failFromSecondCall
    }

    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        guard let destination = arguments.first(where: { $0.contains("@") }),
              let ip = destination.split(separator: "@").last.map(String.init)
        else {
            return Data()
        }
        callCounts[ip, default: 0] += 1
        let isSecondOrLaterCall = callCounts[ip]! >= 2
        if failFromSecondCall.contains(ip), isSecondOrLaterCall {
            return Data()
        }
        return Data("radnok-\(ip)\nNo\n".utf8)
    }
}

/// Pins Fix 2 from the final review: a partial enrichment failure (one host's
/// SSH round-trip fails while another's succeeds) must not drop the failing
/// host's previously known details. Before the fix, the final enrichment
/// assignment unconditionally set `details: details[entry.host.id]`, so any
/// host missing from that tick's `details` dictionary — whether the whole
/// pass failed or just that one host — was reset to nil, even though it had
/// good details from the previous refresh a moment ago.
@MainActor
@Test func partialEnrichmentFailurePreservesThatHostsPreviousDetails() async throws {
    let sshRunner = PerHostSSHRunner(failFromSecondCall: ["100.108.216.101"]) // mbp fails on 2nd refresh
    let store = makeStore(
        runner: StubRunner(json: twoMacsJSON),
        probe: StubProbe(outcomes: [
            "100.123.34.96": .listening,
            "100.108.216.101": .listening,
        ]),
        sshStatus: SSHStatusClient(runner: sshRunner)
    )

    await store.refresh()
    let mini = store.entries.first { $0.host.name == "mini" }
    let mbp = store.entries.first { $0.host.name == "mbp" }
    #expect(mini?.details?.consoleUser == "radnok-100.123.34.96")
    let mbpDetailsAfterFirstRefresh = mbp?.details
    #expect(mbpDetailsAfterFirstRefresh?.consoleUser == "radnok-100.108.216.101")

    // Second refresh: mbp's SSH call now fails (returns nil details), mini's
    // still succeeds.
    await store.refresh()
    let miniAfterSecondRefresh = store.entries.first { $0.host.name == "mini" }
    let mbpAfterSecondRefresh = store.entries.first { $0.host.name == "mbp" }

    // mini's details refresh normally.
    #expect(miniAfterSecondRefresh?.details?.consoleUser == "radnok-100.123.34.96")
    // mbp's enrichment failed this tick, but its details from the first
    // refresh must still be present, not nil.
    #expect(mbpAfterSecondRefresh?.details == mbpDetailsAfterFirstRefresh)
    #expect(mbpAfterSecondRefresh?.details != nil)
}

private let subtitleHost = Host(id: "1", name: "mini", displayName: "Mac mini",
                                ipv4: "100.123.34.96", isOnline: true,
                                source: .tailscale, sshUsername: "radnok")

/// Enrichment only ever runs for `.online` hosts, whose status label is
/// always the longest one ("Screen Sharing nasłuchuje" — ~25 characters on
/// its own). With `.lineLimit(1)` in a ~280pt-wide menu row, keeping that
/// label once `details` are known would push the lock indicator — the whole
/// point of enrichment — off the visible line. `hostSubtitle` drops the
/// status label once `details` are present instead, since the status dot
/// already encodes it and, at that point, it is always "online" anyway.
@Test func subtitleShowsIPAndStatusWhenNoDetails() {
    let entry = HostEntry(host: subtitleHost, status: .online)
    #expect(hostSubtitle(for: entry) == "100.123.34.96 · Screen Sharing nasłuchuje")
}

@Test func subtitleShowsIPAndUserWhenUnlockedWithDetails() {
    let entry = HostEntry(
        host: subtitleHost, status: .online,
        details: HostDetails(consoleUser: "radnok", isScreenLocked: false))
    #expect(hostSubtitle(for: entry) == "100.123.34.96 · radnok")
}

@Test func subtitleAppendsLockedIndicatorWhenLockedWithDetails() {
    let entry = HostEntry(
        host: subtitleHost, status: .online,
        details: HostDetails(consoleUser: "radnok", isScreenLocked: true))
    #expect(hostSubtitle(for: entry) == "100.123.34.96 · radnok · zablokowany")
}

@Test func subtitleOmitsUserWhenDetailsHaveNoConsoleUser() {
    let entry = HostEntry(
        host: subtitleHost, status: .online,
        details: HostDetails(consoleUser: nil, isScreenLocked: true))
    #expect(hostSubtitle(for: entry) == "100.123.34.96 · zablokowany")
}

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

@MainActor
private func makeStore(
    runner: CommandRunning,
    probe: PortProbing,
    launcher: Launching = NoopLauncher()
) -> HostStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("remotemac-store-\(UUID().uuidString)")
        .appendingPathComponent("settings.json")
    return HostStore(
        tailscale: TailscaleClient(runner: runner, executablePath: "/fake/Tailscale"),
        probe: probe,
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

import Foundation
import Testing
@testable import RemoteMac
@testable import RemoteMacCore

/// Guards the panel's loading-state signal composition: the pieces that
/// decide when to show a spinner, "No machines", or a real summary, and when
/// the panel sizer should re-fit the window.
@MainActor
struct MenuViewTests {
    @Test func stateKeyIsLoadingBeforeFirstRefresh() {
        let store = HostStore(settingsStore: SettingsStore(fileURL: Self.tempSettingsURL()))
        #expect(MenuView.stateKey(for: store) == "loading")
    }

    @Test func stateKeyDistinguishesLoadingEmptyAndPopulated() async {
        let store = HostStore(
            tailscale: TailscaleClient(runner: EmptyRunner(), executablePath: "/fake/Tailscale"),
            probe: NoopProbe(),
            settingsStore: SettingsStore(fileURL: Self.tempSettingsURL())
        )
        #expect(MenuView.stateKey(for: store) == "loading")

        await store.refresh()
        #expect(MenuView.stateKey(for: store) == "empty")

        store.settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]
        await store.refresh()
        #expect(MenuView.stateKey(for: store) == "populated")
    }

    @Test func summaryShowsLoadingTextWhileLoading() {
        let store = HostStore(settingsStore: SettingsStore(fileURL: Self.tempSettingsURL()))
        #expect(MenuView.summary(for: store) == store.l10n(.menuLoading))
    }

    @Test func summaryCountsOnlyConnectableHostsAsAvailable() async {
        let store = HostStore(
            tailscale: TailscaleClient(runner: EmptyRunner(), executablePath: "/fake/Tailscale"),
            probe: NoopProbe(),
            settingsStore: SettingsStore(fileURL: Self.tempSettingsURL())
        )
        store.settings.manualHosts = [
            ManualHost(name: "one", address: "10.0.0.1"),
            ManualHost(name: "two", address: "10.0.0.2"),
        ]
        await store.refresh()

        // Manual hosts probe against a real network stub that finds nothing
        // listening, so both entries land as not connectable — the summary
        // must report "0 available", not the total.
        #expect(MenuView.summary(for: store) == store.l10n(.menuHeaderSummary, 2, 0))
    }

    private static func tempSettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remotemac-menuview-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
    }
}

private struct EmptyRunner: CommandRunning {
    func run(executable: String, arguments: [String],
             environment: [String: String], timeout: Duration) async throws -> Data {
        Data("""
        {"BackendState":"Running"}
        """.utf8)
    }
}

private struct NoopProbe: PortProbing {
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        .timedOut
    }
}

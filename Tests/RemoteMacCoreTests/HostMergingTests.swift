import Testing
@testable import RemoteMacCore

private func tailscaleHost(_ name: String, _ ip: String, id: String? = nil) -> Host {
    Host(id: id ?? "nodekey:\(name)", name: name, displayName: name,
         ipv4: ip, isOnline: true, source: .tailscale)
}

@Test func manualHostsAppearAlongsideTailscaleHosts() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.123.34.96")], settings: settings)
    #expect(merged.count == 2)
    #expect(merged.contains { $0.name == "biuro" && $0.source == .manual })
}

@Test func manualHostDuplicatingTailscaleIPIsDropped() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "mini-recznie", address: "100.123.34.96")]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.123.34.96")], settings: settings)
    #expect(merged.count == 1)
    #expect(merged[0].source == .tailscale)
}

@Test func hiddenHostsAreExcluded() {
    var settings = AppSettings.default
    settings.hiddenHostIDs = ["nodekey:mini"]

    let merged = mergeHosts(
        tailscale: [tailscaleHost("mini", "100.123.34.96"), tailscaleHost("mbp", "100.108.216.101")],
        settings: settings
    )
    #expect(merged.map(\.name) == ["mbp"])
}

@Test func manualHostsCarryOfflineUntilProbed() {
    // Manual hosts have no Tailscale online flag, so they start unknown.
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]

    let merged = mergeHosts(tailscale: [], settings: settings)
    #expect(merged[0].isOnline == false)
}

@Test func usernamesAreResolvedPerHost() {
    var settings = AppSettings.default
    settings.defaultSSHUsername = "radnok"
    settings.sshUsernames = ["nodekey:mini": "admin"]

    let merged = mergeHosts(
        tailscale: [tailscaleHost("mini", "100.123.34.96"), tailscaleHost("mbp", "100.108.216.101")],
        settings: settings
    )
    let mini = merged.first { $0.name == "mini" }
    let mbp = merged.first { $0.name == "mbp" }
    #expect(mini?.sshUsername == "admin")
    #expect(mbp?.sshUsername == "radnok")
}

@Test func resultIsSortedByDisplayName() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "aaa", address: "10.0.0.1")]

    let merged = mergeHosts(tailscale: [tailscaleHost("zzz", "100.0.0.1")], settings: settings)
    #expect(merged.map(\.displayName) == ["aaa", "zzz"])
}

@Test func emptyInputsProduceEmptyList() {
    #expect(mergeHosts(tailscale: [], settings: .default).isEmpty)
}

/// The settings pane's "+" button creates an empty row for the user to fill
/// in, and it is persisted as they type. Until it has an address there is
/// nothing to probe, so it must not reach the menu as a phantom machine.
@Test func manualHostWithoutAnAddressIsNotListed() {
    var settings = AppSettings.default
    settings.manualHosts = [
        ManualHost(name: "Name", address: ""),
        ManualHost(name: "blank", address: "   "),
        ManualHost(name: "real", address: "192.168.1.50"),
    ]

    let merged = mergeHosts(tailscale: [], settings: settings)
    #expect(merged.map(\.name) == ["real"])
}

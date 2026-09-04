import Testing
@testable import RemoteMacCore

private func tailscaleHost(_ name: String, _ ip: String, id: String? = nil) -> Host {
    Host(id: id ?? "nodekey:\(name)", name: name, displayName: name,
         ipv4: ip, isOnline: true, source: .tailscale)
}

@Test func manualHostsAppearAlongsideTailscaleHosts() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "biuro", address: "192.168.1.50")]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: settings)
    #expect(merged.count == 2)
    #expect(merged.contains { $0.name == "biuro" && $0.source == .manual })
}

@Test func manualHostDuplicatingTailscaleIPIsDropped() {
    var settings = AppSettings.default
    settings.manualHosts = [ManualHost(name: "mini-recznie", address: "100.64.10.1")]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: settings)
    #expect(merged.count == 1)
    #expect(merged[0].source == .tailscale)
}

@Test func hiddenHostsAreExcluded() {
    var settings = AppSettings.default
    settings.hiddenHostIDs = ["nodekey:mini"]

    let merged = mergeHosts(
        tailscale: [tailscaleHost("mini", "100.64.10.1"), tailscaleHost("mbp", "100.64.10.2")],
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
    settings.defaultSSHUsername = "alex"
    settings.sshUsernames = ["nodekey:mini": "admin"]

    let merged = mergeHosts(
        tailscale: [tailscaleHost("mini", "100.64.10.1"), tailscaleHost("mbp", "100.64.10.2")],
        settings: settings
    )
    let mini = merged.first { $0.name == "mini" }
    let mbp = merged.first { $0.name == "mbp" }
    #expect(mini?.sshUsername == "admin")
    #expect(mbp?.sshUsername == "alex")
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

/// A Tailscale host can be hidden the same way a manual one can — the owner's
/// complaint was that Tailscale machines were not configurable at all, so
/// this must keep working once the Devices tab exposes the toggle.
@Test func hiddenTailscaleHostIsExcluded() {
    var settings = AppSettings.default
    settings.hiddenHostIDs = ["nodekey:mini"]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: settings)
    #expect(merged.isEmpty)
}

@Test func displayNameOverrideWinsOverTailscaleName() {
    var settings = AppSettings.default
    settings.displayNameOverrides = ["nodekey:mini": "Living Room Mac"]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: settings)
    #expect(merged[0].displayName == "Living Room Mac")
}

/// Empty override text means "use the Tailscale/manual name" — see
/// `AppSettings.displayName(for:fallback:)` — the same convention as the SSH
/// username override.
@Test func emptyDisplayNameOverrideFallsBackToSourceName() {
    var settings = AppSettings.default
    settings.displayNameOverrides = ["nodekey:mini": ""]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: settings)
    #expect(merged[0].displayName == "mini")
}

@Test func customPortIsResolvedOntoTheMergedHost() {
    var settings = AppSettings.default
    settings.screenSharingPorts = ["nodekey:mini": 5901]

    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: settings)
    #expect(merged[0].screenSharingPort == 5901)
}

@Test func hostWithoutAPortOverrideKeepsTheDefaultPort() {
    let merged = mergeHosts(tailscale: [tailscaleHost("mini", "100.64.10.1")], settings: .default)
    #expect(merged[0].screenSharingPort == RemoteMacCore.screenSharingPort)
}

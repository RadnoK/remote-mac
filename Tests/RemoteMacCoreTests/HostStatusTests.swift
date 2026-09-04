import Testing
@testable import RemoteMacCore

@Test func listeningPortMeansOnline() {
    #expect(resolveStatus(tailscaleOnline: true, probe: .listening) == .online)
}

@Test func refusedPortMeansScreenSharingOff() {
    #expect(resolveStatus(tailscaleOnline: true, probe: .refused) == .screenSharingOff)
}

@Test func dnsFailureIsDistinctFromClosedPort() {
    // The user's remedy differs, so these must not collapse into one state.
    #expect(resolveStatus(tailscaleOnline: true, probe: .dnsFailure) == .notFound)
}

@Test func timeoutOnOnlineHostMeansOffline() {
    // Unreachable hosts emit no NWConnection state at all; the external
    // timeout is what surfaces a sleeping Mac.
    #expect(resolveStatus(tailscaleOnline: true, probe: .timedOut) == .offline)
}

@Test func unknownTailscaleStateIsNeverReportedAsOffline() {
    // A hung CLI returns no data while the daemon is perfectly healthy.
    #expect(resolveStatus(tailscaleOnline: nil, probe: nil) == .unknown)
}

@Test func probeStillWinsWhenTailscaleStateIsUnknown() {
    #expect(resolveStatus(tailscaleOnline: nil, probe: .listening) == .online)
}

@Test func tailscaleOfflineShortCircuitsWithoutProbe() {
    #expect(resolveStatus(tailscaleOnline: false, probe: nil) == .offline)
}

@Test func pendingProbeOnOnlineHostIsUnknown() {
    #expect(resolveStatus(tailscaleOnline: true, probe: nil) == .unknown)
}

@Test func onlyOnlineIsConnectable() {
    #expect(HostStatus.online.isConnectable)
    #expect(!HostStatus.offline.isConnectable)
    #expect(!HostStatus.unknown.isConnectable)
    #expect(!HostStatus.screenSharingOff.isConnectable)
    #expect(!HostStatus.notFound.isConnectable)
}

@MainActor
@Test func everyStatusHasNonEmptyLabelInEveryLanguage() throws {
    let all: [HostStatus] = [.unknown, .offline, .online, .screenSharingOff, .notFound]
    let bundle = try resourcesBundle()
    for language: AppLanguage in [.en, .pl] {
        let l10n = L10n(language: language, bundles: [bundle])
        #expect(all.allSatisfy { !$0.label(l10n).isEmpty })
    }
    // An open port proves the service answers, not that login will succeed.
    // The label must not overclaim: "Available" is honest, "Connected" or
    // "Ready to connect" would not be. These labels are also rendered in a
    // narrow menu row, so they must stay short enough not to truncate.
    for language: AppLanguage in [.en, .pl] {
        let l10n = L10n(language: language, bundles: [bundle])
        let label = HostStatus.online.label(l10n)
        #expect(label.count <= 16, "status label too long for the row: \(label)")
        for overclaim in ["connect", "połącz", "ready", "gotow"] {
            #expect(!label.lowercased().contains(overclaim),
                    "status label overclaims reachability: \(label)")
        }
    }
}

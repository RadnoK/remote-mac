import Foundation
import Testing
@testable import RemoteMacCore

/// Shaped after real output from `Tailscale status --json` on the target machine.
private let realisticJSON = """
{
  "Version": "1.102.3-t9329c3677-ga522f65e9",
  "BackendState": "Running",
  "TailscaleIPs": ["100.64.10.3"],
  "Self": {
    "ID": "self1",
    "PublicKey": "nodekey:aaa",
    "HostName": "Alex's MacBook",
    "DNSName": "alex-macbook-pro.tailnet-1234.ts.net.",
    "OS": "macOS",
    "TailscaleIPs": ["100.64.10.3", "fd7a:115c:a1e0::1"],
    "Online": true,
    "LastSeen": "0001-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:bbb": {
      "ID": "peer1",
      "PublicKey": "nodekey:bbb",
      "HostName": "Alex’s Mac mini",
      "DNSName": "studio-mac-mini.tailnet-1234.ts.net.",
      "OS": "macOS",
      "TailscaleIPs": ["100.64.10.1", "fd7a:115c:a1e0::2"],
      "Online": true,
      "LastSeen": "0001-01-01T00:00:00Z"
    },
    "nodekey:ccc": {
      "ID": "peer2",
      "PublicKey": "nodekey:ccc",
      "HostName": "build-server",
      "DNSName": "build-server.tailnet-1234.ts.net.",
      "OS": "linux",
      "TailscaleIPs": ["100.84.209.51"],
      "Online": true,
      "LastSeen": "0001-01-01T00:00:00Z",
      "Tags": ["tag:server"]
    },
    "nodekey:ddd": {
      "ID": "peer3",
      "PublicKey": "nodekey:ddd",
      "HostName": "localhost",
      "DNSName": "alex-iphone.tailnet-1234.ts.net.",
      "OS": "iOS",
      "TailscaleIPs": ["100.110.204.67"],
      "Online": true,
      "LastSeen": "0001-01-01T00:00:00Z"
    },
    "nodekey:eee": {
      "ID": "peer4",
      "PublicKey": "nodekey:eee",
      "HostName": "Alex’s MacBook Pro",
      "DNSName": "studio-macbook-pro.tailnet-1234.ts.net.",
      "OS": "macOS",
      "TailscaleIPs": ["100.64.10.2"],
      "Online": false,
      "LastSeen": "2026-01-21T21:02:00.1Z"
    }
  }
}
"""

@Test func parsesOnlyMacsIncludingSelf() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    // 3 Macs: Self + mini + MacBook Pro. Linux and iOS excluded.
    #expect(hosts.count == 3)
    #expect(hosts.allSatisfy { !$0.name.isEmpty })
}

@Test func usesDNSNameFirstSegmentAsName() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let names = Set(hosts.map(\.name))
    #expect(names == ["alex-macbook-pro", "studio-mac-mini", "studio-macbook-pro"])
}

@Test func stripsTrailingDotAndNeverKeepsFQDN() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.allSatisfy { !$0.name.hasSuffix(".") })
    #expect(hosts.allSatisfy { !$0.name.contains("ts.net") })
}

@Test func preservesCurlyApostropheInDisplayName() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let mini = try #require(hosts.first { $0.name == "studio-mac-mini" })
    #expect(mini.displayName == "Alex\u{2019}s Mac mini")
}

@Test func picksIPv4FromTailscaleIPs() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let mini = try #require(hosts.first { $0.name == "studio-mac-mini" })
    #expect(mini.ipv4 == "100.64.10.1")
    #expect(hosts.allSatisfy { !$0.ipv4.contains(":") })
}

@Test func readsOnlineFlag() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    let mbp = try #require(hosts.first { $0.name == "studio-macbook-pro" })
    #expect(mbp.isOnline == false)
    let mini = try #require(hosts.first { $0.name == "studio-mac-mini" })
    #expect(mini.isOnline == true)
}

@Test func selfIsIncludedEvenThoughAbsentFromPeerDictionary() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.contains { $0.name == "alex-macbook-pro" })
}

@Test func toleratesMissingTagsKey() throws {
    // User-owned devices omit "Tags" entirely rather than sending null.
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.count == 3)
}

@Test func detectsGUILaunchFailureDespiteExitCodeZero() {
    let msg = "The Tailscale GUI failed to start: The operation couldn't be completed. (Tailscale.CLIError error 3.)"
    #expect(throws: TailscaleParseError.guiLaunchFailure) {
        try parseTailscaleStatus(Data(msg.utf8))
    }
}

@Test func emptyOutputIsMalformedNotEmptyList() {
    // A hung CLI returns zero bytes; that is "unknown", never "no hosts".
    #expect(throws: TailscaleParseError.malformed) {
        try parseTailscaleStatus(Data())
    }
}

@Test func reportsBackendStateWhenNotRunning() {
    let json = #"{"BackendState":"Stopped","Self":null,"Peer":null}"#
    #expect(throws: TailscaleParseError.notRunning("Stopped")) {
        try parseTailscaleStatus(Data(json.utf8))
    }
}

@Test func hostsAreSortedByDisplayName() throws {
    let hosts = try parseTailscaleStatus(Data(realisticJSON.utf8))
    #expect(hosts.map(\.displayName) == hosts.map(\.displayName).sorted())
}

@Test func allowsHostnameContainingGUIErrorString() throws {
    // Valid JSON with a hostname containing the GUI-error substring should parse normally,
    // not be misclassified as a GUI launch failure.
    let json = #"""
{
  "BackendState": "Running",
  "Self": {
    "PublicKey": "nodekey:test",
    "HostName": "The Tailscale GUI failed to start Server",
    "DNSName": "weird-host.tailnet-1234.ts.net.",
    "OS": "macOS",
    "TailscaleIPs": ["100.99.88.77"],
    "Online": true
  },
  "Peer": null
}
"""#
    let hosts = try parseTailscaleStatus(Data(json.utf8))
    #expect(hosts.count == 1)
    let host = try #require(hosts.first)
    #expect(host.displayName == "The Tailscale GUI failed to start Server")
    #expect(host.ipv4 == "100.99.88.77")
}

@Test func absentBackendStateIsMalformed() {
    // A payload missing the BackendState key entirely should throw .malformed,
    // not proceed as though the backend were Running.
    let json = #"{"Self":null,"Peer":null}"#
    #expect(throws: TailscaleParseError.malformed) {
        try parseTailscaleStatus(Data(json.utf8))
    }
}

import Testing
@testable import RemoteMacCore

private let hosts = [
    Host(id: "1", name: "konrads-mac-mini", displayName: "Konrad\u{2019}s Mac mini",
         ipv4: "100.123.34.96", isOnline: true, source: .tailscale),
    Host(id: "2", name: "konrads-macbook-pro", displayName: "Konrad\u{2019}s MacBook Pro",
         ipv4: "100.108.216.101", isOnline: true, source: .tailscale),
    Host(id: "3", name: "biuro", displayName: "biuro",
         ipv4: "192.168.1.50", isOnline: false, source: .manual),
]

@Test func emptyQueryReturnsEverythingUnchanged() {
    #expect(searchHosts(hosts, query: "") == hosts)
}

@Test func whitespaceOnlyQueryReturnsEverythingUnchanged() {
    // A stray space must not be treated as a real query and re-sort the list.
    #expect(searchHosts(hosts, query: "   ") == hosts)
}

@Test func matchesSubsequenceNotJustPrefix() {
    let results = searchHosts(hosts, query: "mini")
    #expect(results.first?.name == "konrads-mac-mini")
}

@Test func matchesNonContiguousCharacters() {
    // "kmp" should reach "konrads-macbook-pro".
    let results = searchHosts(hosts, query: "kmp")
    #expect(results.contains { $0.name == "konrads-macbook-pro" })
}

@Test func isCaseInsensitive() {
    #expect(searchHosts(hosts, query: "MINI").first?.name == "konrads-mac-mini")
}

@Test func matchesAgainstIPAddress() {
    let results = searchHosts(hosts, query: "192.168")
    #expect(results.first?.name == "biuro")
}

@Test func ignoresTypographicApostropheInDisplayName() {
    // The user types a straight quote; the display name has U+2019.
    let results = searchHosts(hosts, query: "konrad's mac mini")
    #expect(results.first?.name == "konrads-mac-mini")
}

@Test func nonMatchingQueryReturnsNothing() {
    #expect(searchHosts(hosts, query: "zzzzz").isEmpty)
}

@Test func shorterMatchesRankHigher() {
    // "mac" appears in both Macs; the tighter match should come first.
    let results = searchHosts(hosts, query: "mac")
    #expect(results.count == 2)
    #expect(results[0].name == "konrads-mac-mini")
}

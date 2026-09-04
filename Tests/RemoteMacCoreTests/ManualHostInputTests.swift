import Testing
@testable import RemoteMacCore

@Test func sanitizedManualHostTrimsWhitespaceFromNameAndAddress() {
    let host = sanitizedManualHost(name: "  biuro  ", address: "  192.168.1.50  ")
    #expect(host == ManualHost(name: "biuro", address: "192.168.1.50"))
}

@Test func sanitizedManualHostRejectsEmptyName() {
    #expect(sanitizedManualHost(name: "   ", address: "192.168.1.50") == nil)
}

@Test func sanitizedManualHostRejectsEmptyAddress() {
    #expect(sanitizedManualHost(name: "biuro", address: "   ") == nil)
}

@Test func sanitizedManualHostAcceptsAlreadyCleanInput() {
    let host = sanitizedManualHost(name: "biuro", address: "192.168.1.50")
    #expect(host == ManualHost(name: "biuro", address: "192.168.1.50"))
}

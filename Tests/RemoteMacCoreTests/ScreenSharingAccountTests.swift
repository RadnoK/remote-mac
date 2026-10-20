import Foundation
import Testing
@testable import RemoteMacCore

private func candidate(
    _ account: String?, port: Int? = 5900, modified: Date? = nil
) -> KeychainAccountCandidate {
    KeychainAccountCandidate(account: account, port: port, modified: modified)
}

@Test func selectsAccountOnMatchingPort() {
    let candidates = [
        candidate("Jane Appleseed", port: 5900),
        candidate("Sam Doe", port: 5901),
    ]
    #expect(selectAccount(from: candidates, port: 5901) == "Sam Doe")
    #expect(selectAccount(from: candidates, port: 5900) == "Jane Appleseed")
}

@Test func prefersMostRecentlyModified() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let candidates = [
        candidate("Old Account", modified: older),
        candidate("New Account", modified: newer),
    ]
    #expect(selectAccount(from: candidates, port: 5900) == "New Account")
    #expect(selectAccount(from: candidates.reversed(), port: 5900) == "New Account")
}

@Test func skipsEmptyAndMissingAccounts() {
    let candidates = [candidate(""), candidate(nil), candidate("Jane Appleseed")]
    #expect(selectAccount(from: candidates, port: 5900) == "Jane Appleseed")
}

@Test func noMatchReturnsNil() {
    #expect(selectAccount(from: [], port: 5900) == nil)
    #expect(selectAccount(from: [candidate("Jane Appleseed", port: 5901)], port: 5900) == nil)
    #expect(selectAccount(from: [candidate("", port: 5900), candidate(nil)], port: 5900) == nil)
}

/// An entry without a stored port is how Screen Sharing records the default
/// port, so it must match 5900 and nothing else.
@Test func candidateWithoutPortMatchesOnlyTheDefaultPort() {
    let candidates = [candidate("Jane Appleseed", port: nil)]
    #expect(selectAccount(from: candidates, port: 5900) == "Jane Appleseed")
    #expect(selectAccount(from: candidates, port: 5901) == nil)
}

import Foundation
import LocalAuthentication
import Security

/// Finds the account Screen Sharing remembered for a server, so the `vnc://`
/// URL can carry it. Screen Sharing only reuses its stored password, and so
/// skips its password dialog, when the URL's account matches the Keychain
/// entry's account exactly.
public protocol ScreenSharingAccountLookup: Sendable {
    func account(forServer server: String, port: UInt16) -> String?
}

/// The Keychain attributes of one candidate entry, split from the Security
/// framework types so the choice between entries is testable without a
/// Keychain.
public struct KeychainAccountCandidate: Sendable, Equatable {
    public var account: String?
    public var port: Int?
    public var modified: Date?

    public init(account: String?, port: Int?, modified: Date?) {
        self.account = account
        self.port = port
        self.modified = modified
    }
}

/// A candidate with no stored port counts as the default port only: Screen
/// Sharing leaves the port unset for 5900, so treating it as a wildcard would
/// hand a 5900 account to a host listening on another port. Among matches the
/// most recently modified wins, because the newest entry is the one the user
/// last typed a password for.
public func selectAccount(from candidates: [KeychainAccountCandidate], port: UInt16) -> String? {
    candidates
        .filter { ($0.port ?? Int(RemoteMacCore.screenSharingPort)) == Int(port) }
        .filter { !($0.account ?? "").isEmpty }
        .max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }?
        .account
}

/// Reads attributes only, never the secret, so no password is handled and
/// the Keychain does not ask for authorisation.
public struct KeychainScreenSharingAccountLookup: ScreenSharingAccountLookup {
    public init() {}

    public func account(forServer server: String, port: UInt16) -> String? {
        // `kSecUseAuthenticationUIFail` is deprecated; a context that forbids
        // interaction is its replacement and fails the same way.
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            // Deliberately no `kSecAttrProtocol` filter: it does not match
            // the entries Screen Sharing writes, so adding one finds nothing.
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
            // Fail rather than prompt: a locked Keychain must not put an
            // unlock dialog in front of the user on a connect click.
            kSecUseAuthenticationContext: context,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return nil }

        let candidates = items.map {
            KeychainAccountCandidate(
                account: $0[kSecAttrAccount as String] as? String,
                port: ($0[kSecAttrPort as String] as? NSNumber)?.intValue,
                modified: $0[kSecAttrModificationDate as String] as? Date)
        }
        return selectAccount(from: candidates, port: port)
    }
}

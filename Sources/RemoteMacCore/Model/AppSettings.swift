import Foundation

public struct ManualHost: Sendable, Codable, Hashable {
    public var name: String
    public var address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public struct AppSettings: Sendable, Codable, Equatable {
    public var terminal: TerminalKind
    public var defaultSSHUsername: String
    /// Host id → username. Overrides `defaultSSHUsername`.
    public var sshUsernames: [String: String]
    public var manualHosts: [ManualHost]
    public var hiddenHostIDs: [String]
    /// Interface language. `.system` defers to macOS. Not yet exposed in
    /// Settings UI — persisted so a later task can wire up the picker.
    public var language: AppLanguage

    public init(
        terminal: TerminalKind = .ghostty,
        defaultSSHUsername: String = NSUserName(),
        sshUsernames: [String: String] = [:],
        manualHosts: [ManualHost] = [],
        hiddenHostIDs: [String] = [],
        language: AppLanguage = .system
    ) {
        self.terminal = terminal
        self.defaultSSHUsername = defaultSSHUsername
        self.sshUsernames = sshUsernames
        self.manualHosts = manualHosts
        self.hiddenHostIDs = hiddenHostIDs
        self.language = language
    }

    public static let `default` = AppSettings()

    public func sshUsername(for host: Host) -> String {
        sshUsernames[host.id] ?? defaultSSHUsername
    }

    private enum CodingKeys: String, CodingKey {
        case terminal, defaultSSHUsername, sshUsernames, manualHosts, hiddenHostIDs, language
    }

    /// `language` was added after `AppSettings` shipped, so a settings file
    /// written by an older build has no such key. Decoding it with
    /// `decodeIfPresent` keeps that file loadable instead of falling back to
    /// `.default` (and discarding the user's other saved settings) the
    /// moment this field was introduced.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terminal = try container.decode(TerminalKind.self, forKey: .terminal)
        defaultSSHUsername = try container.decode(String.self, forKey: .defaultSSHUsername)
        sshUsernames = try container.decode([String: String].self, forKey: .sshUsernames)
        manualHosts = try container.decode([ManualHost].self, forKey: .manualHosts)
        hiddenHostIDs = try container.decode([String].self, forKey: .hiddenHostIDs)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }
}

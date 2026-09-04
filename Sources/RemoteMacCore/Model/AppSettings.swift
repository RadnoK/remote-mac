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

    public init(
        terminal: TerminalKind = .ghostty,
        defaultSSHUsername: String = NSUserName(),
        sshUsernames: [String: String] = [:],
        manualHosts: [ManualHost] = [],
        hiddenHostIDs: [String] = []
    ) {
        self.terminal = terminal
        self.defaultSSHUsername = defaultSSHUsername
        self.sshUsernames = sshUsernames
        self.manualHosts = manualHosts
        self.hiddenHostIDs = hiddenHostIDs
    }

    public static let `default` = AppSettings()

    public func sshUsername(for host: Host) -> String {
        sshUsernames[host.id] ?? defaultSSHUsername
    }
}

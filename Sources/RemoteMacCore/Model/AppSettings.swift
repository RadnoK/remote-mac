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
    /// Host id → display name. Overrides the Tailscale/manual name shown in
    /// the menu, the quick switcher and search. Absent (or empty, see
    /// `displayName(for:)`) means "use the source's name".
    public var displayNameOverrides: [String: String]
    /// Host id → Screen Sharing (VNC) port. Overrides the default
    /// `screenSharingPort` (5900). Absent means "use the default".
    public var screenSharingPorts: [String: UInt16]
    /// Interface language. `.system` defers to macOS. Not yet exposed in
    /// Settings UI — persisted so a later task can wire up the picker.
    public var language: AppLanguage

    public init(
        terminal: TerminalKind = .ghostty,
        defaultSSHUsername: String = NSUserName(),
        sshUsernames: [String: String] = [:],
        manualHosts: [ManualHost] = [],
        hiddenHostIDs: [String] = [],
        displayNameOverrides: [String: String] = [:],
        screenSharingPorts: [String: UInt16] = [:],
        language: AppLanguage = .system
    ) {
        self.terminal = terminal
        self.defaultSSHUsername = defaultSSHUsername
        self.sshUsernames = sshUsernames
        self.manualHosts = manualHosts
        self.hiddenHostIDs = hiddenHostIDs
        self.displayNameOverrides = displayNameOverrides
        self.screenSharingPorts = screenSharingPorts
        self.language = language
    }

    public static let `default` = AppSettings()

    /// The SSH username to use for `host`: its own override if one is set,
    /// otherwise `defaultSSHUsername`. An override is only ever stored
    /// non-empty — see `HostStore`/the Devices settings pane, which removes
    /// the key entirely rather than persisting "" — but this is defensive
    /// about an empty string surviving anyway (e.g. a hand-edited
    /// settings.json).
    public func sshUsername(for host: Host) -> String {
        let override = sshUsernames[host.id]
        return (override?.isEmpty == false) ? override! : defaultSSHUsername
    }

    /// The display name to use for `host`: its own override if one is set,
    /// otherwise `fallback` (the Tailscale/manual name). Same empty-string
    /// defensiveness as `sshUsername(for:)`.
    public func displayName(for host: Host, fallback: String) -> String {
        let override = displayNameOverrides[host.id]
        return (override?.isEmpty == false) ? override! : fallback
    }

    /// The Screen Sharing port to use for `host`: its own override if one is
    /// set, otherwise the global default (5900).
    public func screenSharingPort(for host: Host) -> UInt16 {
        screenSharingPorts[host.id] ?? RemoteMacCore.screenSharingPort
    }

    private enum CodingKeys: String, CodingKey {
        case terminal, defaultSSHUsername, sshUsernames, manualHosts, hiddenHostIDs
        case displayNameOverrides, screenSharingPorts, language
    }

    /// `language` was added after `AppSettings` shipped, so a settings file
    /// written by an older build has no such key. Decoding it with
    /// `decodeIfPresent` keeps that file loadable instead of falling back to
    /// `.default` (and discarding the user's other saved settings) the
    /// moment this field was introduced. `displayNameOverrides` and
    /// `screenSharingPorts` follow the same pattern for the same reason.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terminal = try container.decode(TerminalKind.self, forKey: .terminal)
        defaultSSHUsername = try container.decode(String.self, forKey: .defaultSSHUsername)
        sshUsernames = try container.decode([String: String].self, forKey: .sshUsernames)
        manualHosts = try container.decode([ManualHost].self, forKey: .manualHosts)
        hiddenHostIDs = try container.decode([String].self, forKey: .hiddenHostIDs)
        displayNameOverrides = try container.decodeIfPresent(
            [String: String].self, forKey: .displayNameOverrides) ?? [:]
        screenSharingPorts = try container.decodeIfPresent(
            [String: UInt16].self, forKey: .screenSharingPorts) ?? [:]
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }
}

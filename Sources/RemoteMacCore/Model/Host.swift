import Foundation

public enum HostSource: String, Sendable, Codable, Hashable {
    case tailscale
    case manual
}

public struct Host: Sendable, Identifiable, Hashable, Codable {
    /// Stable identity. For Tailscale hosts this is the node's public key;
    /// for manual hosts it is the user-supplied address.
    public let id: String
    /// DNS-safe short name, suitable for SSH. Never contains a trailing dot.
    public let name: String
    /// Human-facing label. May contain a typographic apostrophe (U+2019).
    public let displayName: String
    public let ipv4: String
    public let isOnline: Bool
    public let source: HostSource
    public var sshUsername: String?

    public init(
        id: String,
        name: String,
        displayName: String,
        ipv4: String,
        isOnline: Bool,
        source: HostSource,
        sshUsername: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.ipv4 = ipv4
        self.isOnline = isOnline
        self.source = source
        self.sshUsername = sshUsername
    }
}

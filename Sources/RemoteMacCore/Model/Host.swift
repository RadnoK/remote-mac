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
    /// `var` because `mergeHosts` overwrites it with the user's
    /// `AppSettings.displayNameOverrides` entry, if one is set, so every
    /// consumer (menu, quick switcher, search) sees the same resolved name.
    public var displayName: String
    public let ipv4: String
    public let isOnline: Bool
    public let source: HostSource
    public var sshUsername: String?
    /// Screen Sharing (VNC) port. Defaults to the well-known `screenSharingPort`
    /// (5900) and is only ever overridden by `mergeHosts` resolving a
    /// per-host `AppSettings.screenSharingPorts` entry — carrying the
    /// resolved value on `Host` itself means `HostStore.refresh()`'s probe
    /// and `screenSharingURL(for:)` both read the same number instead of one
    /// of them silently falling back to the global default.
    public var screenSharingPort: UInt16

    public init(
        id: String,
        name: String,
        displayName: String,
        ipv4: String,
        isOnline: Bool,
        source: HostSource,
        sshUsername: String? = nil,
        screenSharingPort: UInt16 = RemoteMacCore.screenSharingPort
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.ipv4 = ipv4
        self.isOnline = isOnline
        self.source = source
        self.sshUsername = sshUsername
        self.screenSharingPort = screenSharingPort
    }
}

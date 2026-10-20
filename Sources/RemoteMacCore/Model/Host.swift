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
    /// Whether this Mac shares a LAN with us, so a fast connection mode is
    /// safe to pick. For Tailscale hosts it comes from `CurAddr`, the physical
    /// endpoint of a direct path: a private address there means the peers sit
    /// on the same network, while an empty value means the traffic is relayed
    /// or idle and says nothing about locality. The tailnet IP in `ipv4`
    /// (100.64.0.0/10) cannot answer this, because it is the same wherever the
    /// peer is. Manual hosts use their own address instead.
    public var isOnLocalNetwork: Bool
    /// How to answer Screen Sharing's Standard / High Performance chooser.
    /// Resolved by `mergeHosts` from `AppSettings.screenSharingTypes`.
    public var screenSharingType: ScreenSharingTypePreference

    public init(
        id: String,
        name: String,
        displayName: String,
        ipv4: String,
        isOnline: Bool,
        source: HostSource,
        sshUsername: String? = nil,
        screenSharingPort: UInt16 = RemoteMacCore.screenSharingPort,
        isOnLocalNetwork: Bool = false,
        screenSharingType: ScreenSharingTypePreference = .auto
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.ipv4 = ipv4
        self.isOnline = isOnline
        self.source = source
        self.sshUsername = sshUsername
        self.screenSharingPort = screenSharingPort
        self.isOnLocalNetwork = isOnLocalNetwork
        self.screenSharingType = screenSharingType
    }
}

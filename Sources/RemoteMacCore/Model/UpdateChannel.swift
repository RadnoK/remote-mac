import Foundation

/// Which stream of releases this install follows.
///
/// Stored as a bare string in UserDefaults next to Sparkle's own
/// preferences, so `init(storedValue:)` is the only way in: anything
/// unrecognised means stable, the channel a user who never opened the
/// Updates tab expects to be on.
public enum UpdateChannel: String, CaseIterable, Sendable {
    case stable
    case beta

    /// The UserDefaults key the choice lives under.
    public static let defaultsKey = "updateChannel"

    public init(storedValue: String?) {
        self = storedValue.flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }

    /// The feed Sparkle reads for this channel. Both are served from the
    /// `gh-pages` branch: a stable release is written to both, a beta only
    /// to the beta one, so beta testers get stable releases too.
    public var appcastURL: URL {
        switch self {
        case .stable: URL(string: "https://radnok.github.io/remote-mac/appcast.xml")!
        case .beta: URL(string: "https://radnok.github.io/remote-mac/appcast-beta.xml")!
        }
    }

    public var labelKey: LocKey {
        switch self {
        case .stable: .settingsChannelStable
        case .beta: .settingsChannelBeta
        }
    }
}

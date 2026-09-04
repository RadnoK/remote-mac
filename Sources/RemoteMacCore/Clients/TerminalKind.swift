import Foundation

public enum TerminalKind: String, Sendable, Codable, CaseIterable, Hashable {
    case ghostty
    case iterm
    case terminal
    case warp
    case termius

    public var bundleIdentifier: String {
        switch self {
        case .ghostty:  "com.mitchellh.ghostty"
        case .iterm:    "com.googlecode.iterm2"
        case .terminal: "com.apple.Terminal"
        case .warp:     "dev.warp.Warp-Stable"
        case .termius:  "com.termius.mac"
        }
    }

    public var displayName: String {
        switch self {
        case .ghostty:  "Ghostty"
        case .iterm:    "iTerm2"
        case .terminal: "Terminal"
        case .warp:     "Warp"
        case .termius:  "Termius"
        }
    }

    /// True when driving this terminal requires an AppleEvents (Automation)
    /// TCC grant. Only Terminal.app does.
    public var requiresAppleEvents: Bool {
        self == .terminal
    }
}

import Foundation

/// User-selectable interface language. `.system` defers to macOS.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case pl
    case en

    /// English is the base language, so anything we do not translate lands there.
    public static let base = "en"

    /// Resolves to a concrete `.lproj` code. Only the first preferred language
    /// counts: a user whose primary language is German gets English, even if
    /// Polish appears further down their list.
    public static func resolvedCode(for language: AppLanguage, preferred: [String]) -> String {
        switch language {
        case .pl: return "pl"
        case .en: return base
        case .system:
            guard let first = preferred.first else { return base }
            return first.hasPrefix("pl") ? "pl" : base
        }
    }

    public var resolvedCode: String {
        Self.resolvedCode(for: self, preferred: Locale.preferredLanguages)
    }
}

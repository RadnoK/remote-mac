import Foundation
import Observation

/// Resolves `LocKey` values against the active language's `.lproj` bundle.
///
/// Injected rather than global so tests can build an instance for any language
/// and so a language change re-renders observing views automatically.
@MainActor
@Observable
public final class L10n {
    public private(set) var language: AppLanguage
    private let searchBundles: [Bundle]

    /// Where to look for `.lproj` directories. Only `Bundle.main` is used: the
    /// assembled `.app` carries `en.lproj` and `pl.lproj` in `Contents/Resources`.
    /// Deliberately no `Bundle.module` — declaring SwiftPM resources makes the
    /// release accessor `fatalError` when the synthesized bundle is absent from
    /// the hand-assembled `.app`, which crashed the app on launch.
    public static var defaultBundles: [Bundle] { [Bundle.main] }

    public init(language: AppLanguage = .system, bundles: [Bundle] = L10n.defaultBundles) {
        self.language = language
        self.searchBundles = bundles
    }

    public var resolvedCode: String { language.resolvedCode }

    /// Used by date and number formatters so they match the interface language.
    public var locale: Locale { Locale(identifier: resolvedCode) }

    public func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    public func callAsFunction(_ key: LocKey) -> String {
        lookup(key.rawValue)
    }

    public func callAsFunction(_ key: LocKey, _ args: CVarArg...) -> String {
        String(format: lookup(key.rawValue), locale: locale, arguments: args)
    }

    /// Resolved `.lproj`, then the English base table, then the raw key. A
    /// missing string stays visible instead of rendering as empty text.
    private func lookup(_ key: String) -> String {
        for code in [resolvedCode, AppLanguage.base] {
            for bundle in searchBundles {
                guard let path = bundle.path(forResource: code, ofType: "lproj"),
                      let lproj = Bundle(path: path) else { continue }
                let value = lproj.localizedString(forKey: key, value: Self.missing, table: nil)
                if value != Self.missing { return value }
            }
        }
        return key
    }

    private static let missing = "\u{0}__missing__"
}

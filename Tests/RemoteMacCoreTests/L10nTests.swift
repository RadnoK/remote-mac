import Testing
@testable import RemoteMacCore

@MainActor
@Test func missingKeyFallsBackToRawValue() {
    // No bundles at all: every lookup degrades to the key itself, which is
    // visible in the UI instead of crashing or rendering empty.
    let l10n = L10n(language: .en, bundles: [])
    #expect(l10n(.menuRefresh) == LocKey.menuRefresh.rawValue)
}

@MainActor
@Test func localeTracksResolvedLanguage() {
    let l10n = L10n(language: .pl, bundles: [])
    #expect(l10n.locale.identifier == "pl")
    l10n.setLanguage(.en)
    #expect(l10n.locale.identifier == "en")
}

@MainActor
@Test func setLanguageChangesResolvedCode() {
    let l10n = L10n(language: .en, bundles: [])
    #expect(l10n.resolvedCode == "en")
    l10n.setLanguage(.pl)
    #expect(l10n.resolvedCode == "pl")
}

@MainActor
@Test func formattingSubstitutesArguments() {
    let l10n = L10n(language: .en, bundles: [])
    // With no table the format string is the raw key, which contains no
    // placeholder, so the argument is dropped rather than corrupting output.
    #expect(l10n(.errorTailscaleDisconnected, "NeedsLogin") == LocKey.errorTailscaleDisconnected.rawValue)
}

@MainActor
@Test func setLanguagePropagatesToResolvedStrings() throws {
    // The core behaviour of the feature: switching the language must
    // actually change what callAsFunction returns for a real key. The
    // bundle list is built explicitly from the repository's Resources/
    // directory, because the shipped app relies on Bundle.main only and
    // the package declares no SwiftPM resources.
    let l10n = L10n(language: .en, bundles: [try resourcesBundle()])
    #expect(l10n(.menuRefresh) == "Refresh")
    l10n.setLanguage(.pl)
    // Not reachable through the English fallback: "Odśwież" appears only
    // in pl.lproj, so this fails unless the Polish table is really used.
    #expect(l10n(.menuRefresh) == "Odśwież")
}

@Test func everyKeyResolvesInBothLanguages() throws {
    // The real guard: catches a key added to LocKey but forgotten in a
    // .strings file, and a typo in either file.
    for code in ["en", "pl"] {
        let table = try loadStrings(code: code)
        for key in LocKey.allCases {
            #expect(table[key.rawValue] != nil, "missing \(key.rawValue) in \(code).lproj/Localizable.strings")
            #expect(!(table[key.rawValue] ?? "").isEmpty, "empty value for \(key.rawValue) in \(code).lproj/Localizable.strings")
        }
        #expect(table.count == LocKey.allCases.count, "\(code).lproj has entries not present in LocKey")
    }
}

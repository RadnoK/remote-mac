import Testing
@testable import RemoteMacCore

@Test func explicitLanguageIgnoresSystemPreferences() {
    #expect(AppLanguage.resolvedCode(for: .pl, preferred: ["en-US"]) == "pl")
    #expect(AppLanguage.resolvedCode(for: .en, preferred: ["pl-PL"]) == "en")
}

@Test func systemResolvesPolishPreferenceToPolish() {
    #expect(AppLanguage.resolvedCode(for: .system, preferred: ["pl-PL", "en-US"]) == "pl")
    #expect(AppLanguage.resolvedCode(for: .system, preferred: ["pl"]) == "pl")
}

@Test func systemFallsBackToEnglishForOtherLanguages() {
    #expect(AppLanguage.resolvedCode(for: .system, preferred: ["de-DE", "pl-PL"]) == "en")
    #expect(AppLanguage.resolvedCode(for: .system, preferred: []) == "en")
}

@Test func allCasesAreStableRawValues() {
    #expect(AppLanguage.allCases.map(\.rawValue) == ["system", "pl", "en"])
}

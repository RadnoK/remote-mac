import Testing
@testable import RemoteMacCore

struct ResolutionCase: Sendable, CustomTestStringConvertible {
    let preference: ScreenSharingTypePreference
    let isOnLocalNetwork: Bool
    let expected: ScreenSharingType?

    var testDescription: String {
        "\(preference.rawValue), LAN \(isOnLocalNetwork) -> \(String(describing: expected))"
    }
}

@Suite struct ScreenSharingTypeTests {
    @Test(arguments: [
        ResolutionCase(preference: .auto, isOnLocalNetwork: true, expected: .highPerformance),
        ResolutionCase(preference: .auto, isOnLocalNetwork: false, expected: .standard),
        ResolutionCase(preference: .standard, isOnLocalNetwork: true, expected: .standard),
        ResolutionCase(preference: .standard, isOnLocalNetwork: false, expected: .standard),
        ResolutionCase(preference: .highPerformance, isOnLocalNetwork: true, expected: .highPerformance),
        ResolutionCase(preference: .highPerformance, isOnLocalNetwork: false, expected: .highPerformance),
        ResolutionCase(preference: .ask, isOnLocalNetwork: true, expected: nil),
        ResolutionCase(preference: .ask, isOnLocalNetwork: false, expected: nil),
    ])
    func resolutionTable(_ testCase: ResolutionCase) {
        #expect(
            resolveScreenSharingType(
                preference: testCase.preference,
                isOnLocalNetwork: testCase.isOnLocalNetwork
            ) == testCase.expected
        )
    }
}

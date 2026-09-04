import Testing
@testable import RemoteMacCore

@Test func packageExposesVersion() {
    #expect(RemoteMacVersion.version == "1.0")
}

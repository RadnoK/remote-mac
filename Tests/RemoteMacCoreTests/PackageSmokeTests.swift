import Testing
@testable import RemoteMacCore

@Test func packageExposesVersion() {
    #expect(RemoteMacCore.version == "1.0")
}

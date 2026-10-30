import Foundation
import Testing
@testable import RemoteMacCore

@Suite struct UpdateChannelTests {
    @Test func unknownOrMissingValueMeansStable() {
        #expect(UpdateChannel(storedValue: nil) == .stable)
        #expect(UpdateChannel(storedValue: "") == .stable)
        #expect(UpdateChannel(storedValue: "nightly") == .stable)
    }

    @Test func storedValuesRoundTrip() {
        for channel in UpdateChannel.allCases {
            #expect(UpdateChannel(storedValue: channel.rawValue) == channel)
        }
    }

    /// Stable must keep reading the feed every installed copy already knows
    /// (SUFeedURL), or stable users would stop getting updates.
    @Test func stableReadsTheFeedFromInfoPlist() {
        #expect(UpdateChannel.stable.appcastURL.absoluteString
                == "https://radnok.github.io/remote-mac/appcast.xml")
        #expect(UpdateChannel.beta.appcastURL.absoluteString
                == "https://radnok.github.io/remote-mac/appcast-beta.xml")
    }
}

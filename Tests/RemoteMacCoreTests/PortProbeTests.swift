import Foundation
import Network
import Testing
@testable import RemoteMacCore

@Test func screenSharingPortIs5900() {
    #expect(screenSharingPort == 5900)
}

@Test func refusedPortReturnsQuicklyNotAfterFullTimeout() async {
    // NWConnection surfaces "connection refused" as .waiting. Without
    // handling that state this stalls for the whole timeout.
    let probe = NetworkPortProbe()
    let clock = ContinuousClock()
    let start = clock.now
    // Port 1 on localhost is closed but reachable, so it is refused immediately.
    let outcome = await probe.probe(host: "127.0.0.1", port: 1, timeout: .seconds(3))
    let elapsed = clock.now - start

    #expect(outcome == .refused)
    #expect(elapsed < .seconds(1))
}

@Test func unroutableAddressTimesOutAndDoesNotHangForever() async {
    // Unreachable hosts emit no state after .preparing, so only the external
    // deadline ends this.
    let probe = NetworkPortProbe()
    let clock = ContinuousClock()
    let start = clock.now
    let outcome = await probe.probe(host: "192.0.2.1", port: 5900, timeout: .milliseconds(600))
    let elapsed = clock.now - start

    #expect(outcome == .timedOut)
    #expect(elapsed < .seconds(3))
}

@Test func unresolvableNameIsDNSFailureNotRefused() async {
    // The user's remedy differs between "port shut" and "name does not resolve".
    let probe = NetworkPortProbe()
    let outcome = await probe.probe(
        host: "nonexistent-host-\(UUID().uuidString).invalid",
        port: 5900,
        timeout: .seconds(3)
    )
    #expect(outcome == .dnsFailure)
}

@Test func listeningPortIsDetected() async throws {
    // Bind an ephemeral listener and confirm the probe sees it.
    let listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { $0.cancel() }
    listener.start(queue: .global())
    defer { listener.cancel() }

    var port: UInt16?
    for _ in 0..<50 {
        // `listener.port` briefly reports 0 right after `start()`, before the
        // listener reaches `.ready` and the kernel has actually assigned an
        // ephemeral port. Skip that transient value so we don't hand the
        // probe an unbindable port 0 (which fails fast as EADDRNOTAVAIL,
        // misread by the probe as a refused connection).
        if let value = listener.port?.rawValue, value != 0 { port = value; break }
        try await Task.sleep(for: .milliseconds(20))
    }
    let boundPort = try #require(port)

    let outcome = await NetworkPortProbe().probe(
        host: "127.0.0.1", port: boundPort, timeout: .seconds(3))
    #expect(outcome == .listening)
}

// MARK: - classify()
//
// Unit-tested directly against NWError values rather than through the
// network: `.refused` must be reserved for the one error that actually
// proves a closed port. Every other error must fall back to `.timedOut`
// ("Offline"), not `.refused` ("Sharing off") — an unrecognized
// error means we failed to reach the host, not that we learned its Screen
// Sharing is off.

@Test func connectionRefusedIsRefused() {
    #expect(classify(.posix(.ECONNREFUSED)) == .refused)
}

@Test func hostUnreachableIsTimedOutNotRefused() {
    #expect(classify(.posix(.EHOSTUNREACH)) == .timedOut)
}

@Test func networkDownIsTimedOutNotRefused() {
    #expect(classify(.posix(.ENETDOWN)) == .timedOut)
}

@Test func dnsNoSuchRecordIsDNSFailure() {
    #expect(classify(.dns(Int32(kDNSServiceErr_NoSuchRecord))) == .dnsFailure)
}

@Test func dnsTimeoutIsTimedOutNotDNSFailureNotRefused() {
    let outcome = classify(.dns(Int32(kDNSServiceErr_Timeout)))
    #expect(outcome == .timedOut)
    #expect(outcome != .dnsFailure)
    #expect(outcome != .refused)
}

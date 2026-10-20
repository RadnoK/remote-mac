import Testing
@testable import RemoteMacCore

@Test(arguments: [
    "10.1.2.3",
    "10.1.2.3:41641",
    "172.16.0.1",
    "172.31.255.255:1",
    "192.168.18.62:1028",
    "169.254.1.1",
    "[fd7a:115c::1]:41641",
    "fe80::1",
    "[fe80::1]:5900",
    "[::ffff:192.168.1.5]:41641",
])
func privateEndpointsAreRecognised(endpoint: String) {
    #expect(isPrivateEndpoint(endpoint))
}

@Test(arguments: [
    "",
    "garbage",
    "172.15.255.255",
    "172.32.0.1",
    "8.8.8.8:41641",
    // Tailscale's CGNAT range is not the local network.
    "100.64.10.1",
    "100.127.0.1:5900",
    "[2001:db8::1]:41641",
    "mini.local",
    // Network accepts short forms; only a canonical dotted quad may count.
    "192.168.1",
])
func nonPrivateEndpointsAreRejected(endpoint: String) {
    #expect(!isPrivateEndpoint(endpoint))
}

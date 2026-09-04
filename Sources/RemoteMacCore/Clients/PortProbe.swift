import Foundation
import Network
import os

public let screenSharingPort: UInt16 = 5900

public protocol PortProbing: Sendable {
    func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome
}

/// TCP reachability check via Network.framework.
///
/// Two behaviours drive this implementation:
/// 1. A refused connection arrives as `.waiting`, never `.failed`. Without
///    treating `.waiting` as closed, every shut port stalls for the full
///    timeout (2 s instead of 8 ms).
/// 2. An unreachable host emits no state at all after `.preparing`. Handling
///    `.waiting` does not cover it; only the external deadline does.
public struct NetworkPortProbe: PortProbing, Sendable {
    public init() {}

    public func probe(host: String, port: UInt16, timeout: Duration) async -> ProbeOutcome {
        // NWEndpoint.Port(rawValue:) never returns nil for a UInt16 — 0 is
        // valid and maps to `.any` — so this unwrap cannot fail.
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )

        // A task group's implicit exit waits for every child task to finish,
        // even after cancelAll() — cancellation is cooperative, and the
        // connection task below only checks it via a cancellation handler.
        // An unreachable host never emits a state after `.preparing`, so if
        // nothing actively cancels the NWConnection, the connection task
        // (and therefore the whole group) hangs until the OS's own SYN retry
        // timeout gives up — tens of seconds, not our `timeout`. The timeout
        // branch below must cancel the connection itself so the state
        // handler observes `.cancelled` and resumes the continuation,
        // letting the group's implicit final await complete promptly.
        let outcome = await withTaskGroup(of: ProbeOutcome?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let resumed = OSAllocatedUnfairLock(initialState: false)

                    @Sendable func finish(_ result: ProbeOutcome) {
                        let alreadyResumed = resumed.withLock { state -> Bool in
                            if state { return true }
                            state = true
                            return false
                        }
                        guard !alreadyResumed else { return }
                        continuation.resume(returning: result)
                    }

                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            finish(.listening)
                        case let .waiting(error):
                            finish(classify(error))
                        case let .failed(error):
                            finish(classify(error))
                        case .cancelled:
                            finish(.timedOut)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                // `try?` swallows CancellationError, so this line runs
                // whether the sleep completed normally (real timeout) or was
                // cancelled early because the connection task already won
                // the race via group.cancelAll() below — i.e. this call to
                // connection.cancel() happens on every probe, not only on
                // the timeout path. That is fine: NWConnection.cancel() is
                // idempotent, and finish() is lock-guarded against a second
                // resume, so an extra `.cancelled` callback after the
                // connection already resolved is a harmless no-op. What
                // actually matters is the timeout case: only an explicit
                // connection.cancel() forces the NWConnection's state
                // handler to fire `.cancelled` and resume the still-pending
                // continuation — group.cancelAll() alone only marks the
                // *task* cancelled and would leave the connection task (and
                // therefore this whole group) waiting on the OS's own SYN
                // retry timeout instead of `timeout`.
                connection.cancel()
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .timedOut
        }

        connection.cancel()
        return outcome
    }
}

/// Distinguishes a shut port from a name that does not resolve, because the
/// user's remedy differs.
///
/// `.refused` is reserved for the one error that actually proves a closed
/// port: POSIX `ECONNREFUSED`. Every other error — `EHOSTUNREACH`,
/// `ENETUNREACH`, `ENETDOWN`, a DNS timeout, etc. — maps to `.timedOut`
/// rather than `.refused`, deliberately, even though some of those errors
/// arrive quickly rather than after the full deadline. This app probes every
/// host every 30 seconds over Tailscale; interface renegotiation, a Wi-Fi/
/// Ethernet switch, sleep/wake, or a VPN reconnect all surface as exactly
/// these errors on a perfectly healthy Mac. `.refused` renders to the user
/// as "Screen Sharing wyłączony" — a specific, confident claim about the
/// remote machine's configuration. An unrecognized error means we failed to
/// reach the host; it tells us nothing about whether Screen Sharing is
/// enabled there, so the honest, conservative outcome is `.timedOut`
/// ("Offline"), not `.refused`.
func classify(_ error: NWError) -> ProbeOutcome {
    switch error {
    case let .posix(code) where code == .ECONNREFUSED:
        return .refused
    case let .dns(code) where code == kDNSServiceErr_NoSuchRecord:
        return .dnsFailure
    default:
        return .timedOut
    }
}

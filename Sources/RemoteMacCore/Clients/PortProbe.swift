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
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .timedOut }

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
                // Cancelling here (rather than relying on cancelAll() below)
                // is what actually unblocks the connection task: it forces
                // the NWConnection's state handler to fire `.cancelled`,
                // which resumes the pending continuation.
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
private func classify(_ error: NWError) -> ProbeOutcome {
    switch error {
    case let .posix(code) where code == .ECONNREFUSED:
        return .refused
    case let .dns(code) where code == kDNSServiceErr_NoSuchRecord:
        return .dnsFailure
    default:
        return .refused
    }
}

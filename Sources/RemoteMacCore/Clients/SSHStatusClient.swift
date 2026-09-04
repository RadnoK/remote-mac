import Foundation

public struct HostDetails: Sendable, Equatable {
    public let consoleUser: String?
    public let isScreenLocked: Bool?

    public init(consoleUser: String?, isScreenLocked: Bool?) {
        self.consoleUser = consoleUser
        self.isScreenLocked = isScreenLocked
    }
}

/// Reads console user and lock state from a single `ioreg` call.
///
/// `IOConsoleUsers[0]` carries the session user and `IOConsoleLocked` the lock
/// flag. `CGSSessionScreenIsLocked` — the commonly cited key — returns nothing
/// on macOS 26, and `CGSession` no longer exists.
private let consoleStateCommand = """
stat -f%Su /dev/console; \
ioreg -n Root -d1 -k IOConsoleLocked \
  | awk -F'= ' '/IOConsoleLocked/{print $2}' \
  | tr -d ' '
"""

public func parseConsoleState(_ output: String) -> HostDetails {
    let lines = output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    let rawUser = lines.first.flatMap { $0.isEmpty ? nil : $0 }
    // `root` at the console means the login window is showing, not a session.
    let consoleUser = rawUser == "root" ? nil : rawUser

    let lockedValue = lines.count > 1 ? lines[1] : ""
    let isScreenLocked: Bool? = switch lockedValue {
    case "Yes", "true": true
    case "No", "false": false
    default: nil
    }

    return HostDetails(consoleUser: consoleUser, isScreenLocked: isScreenLocked)
}

/// Optional enrichment. Returns nil whenever SSH is not usable — the host list
/// must never depend on it.
public struct SSHStatusClient: Sendable {
    private let runner: CommandRunning
    private let timeout: Duration

    public init(runner: CommandRunning = SubprocessRunner(), timeout: Duration = .seconds(4)) {
        self.runner = runner
        self.timeout = timeout
    }

    public func fetchDetails(host: Host) async -> HostDetails? {
        guard let user = host.sshUsername, !user.isEmpty else { return nil }

        // BatchMode is the real control: ConnectTimeout bounds the connect
        // phase only, so a password prompt would otherwise hang past it.
        let arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=3",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(user)@\(host.ipv4)",
            consoleStateCommand,
        ]

        guard let data = try? await runner.run(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            timeout: timeout
        ), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        return parseConsoleState(text)
    }
}

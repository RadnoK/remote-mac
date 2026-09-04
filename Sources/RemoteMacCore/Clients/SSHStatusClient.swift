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

/// Parses the trailing two non-empty lines of `output` as console user and
/// lock state, reading from the END rather than the start. `consoleStateCommand`
/// runs two commands in sequence, so its two lines of output are always the
/// *last* two things written — reading from the end stays correct even if an
/// MOTD, login banner, or shell rc file prints extra lines first. Reading
/// from the start (the original approach) would let any such banner shift
/// every field, silently misattributing a banner line as the console user.
public func parseConsoleState(_ output: String) -> HostDetails {
    let usableLines = output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    guard usableLines.count >= 2 else {
        // Fewer than two usable lines is not enough to trust either field —
        // guessing which single line is which would be worse than nil.
        return HostDetails(consoleUser: nil, isScreenLocked: nil)
    }

    let rawUser = usableLines[usableLines.count - 2]
    // `root` at the console means the login window is showing, not a session.
    let consoleUser = rawUser == "root" ? nil : rawUser

    let lockedValue = usableLines[usableLines.count - 1]
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

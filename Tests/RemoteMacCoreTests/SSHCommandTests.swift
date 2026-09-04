import Testing
@testable import RemoteMacCore

@Test func ghosttyPassesArgvWithoutShell() {
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "100.123.34.96", isRunning: false)
    #expect(plan == .openWithArguments(
        bundleID: "com.mitchellh.ghostty",
        arguments: ["-e", "ssh", "radnok@100.123.34.96"],
        newInstance: true
    ))
}

@Test func itermUsesEqualsFormOnly() {
    // The space-separated form silently does nothing; only --command=X works.
    let plan = launchPlan(for: .iterm, user: "radnok", host: "100.123.34.96", isRunning: false)
    guard case let .openWithArguments(bundleID, arguments, _) = plan else {
        Issue.record("expected openWithArguments, got \(plan)")
        return
    }
    #expect(bundleID == "com.googlecode.iterm2")
    #expect(arguments.count == 1)
    #expect(arguments[0].hasPrefix("--command="))
    #expect(!arguments.contains("--command"))
}

@Test func itermSkipsNewInstanceWhenAlreadyRunning() {
    // `open -na iTerm` spawns a second iTerm process every time.
    let cold = launchPlan(for: .iterm, user: "radnok", host: "h", isRunning: false)
    let warm = launchPlan(for: .iterm, user: "radnok", host: "h", isRunning: true)
    guard case let .openWithArguments(_, _, coldNew) = cold,
          case let .openWithArguments(_, _, warmNew) = warm else {
        Issue.record("expected openWithArguments")
        return
    }
    #expect(coldNew == true)
    #expect(warmNew == false)
}

@Test func itermEscapesShellMetacharactersWithPOSIXQuoting() {
    // iTerm re-parses the string via `login … $SHELL -c`, so all characters
    // including newline must be protected. POSIX single-quoting is safe:
    // no character is special inside '...'.
    let hostnames = [
        "h;touch /tmp/x",      // semicolon command injection
        "h>/tmp/x",            // output redirection
        "h<in",                // input redirection
        "h*",                  // glob expansion
        "h$(id)",              // command substitution
        "h`id`",               // command substitution
        "h\nrm -rf x"          // newline - parsed as second command
    ]

    for hostname in hostnames {
        let plan = launchPlan(for: .iterm, user: "radnok", host: hostname, isRunning: false)
        guard case let .openWithArguments(_, arguments, _) = plan else {
            Issue.record("expected openWithArguments for hostname \(hostname)")
            return
        }
        let arg = arguments[0]

        // Argument must be --command=<single-quoted-string>
        #expect(arg.hasPrefix("--command="))
        let quotedContent = String(arg.dropFirst("--command=".count))

        // Must start and end with single quote
        #expect(quotedContent.hasPrefix("'"))
        #expect(quotedContent.hasSuffix("'"))

        // Interior must be properly quoted: no unescaped single quotes
        // Valid patterns: regular chars or '\'' (end quote, escaped quote, start quote)
        let interior = String(quotedContent.dropFirst().dropLast())
        var i = interior.startIndex
        while i < interior.endIndex {
            let char = interior[i]
            if char == "'" {
                // Single quote must be preceded by backslash and followed by single quote
                // pattern: \''  (actually '\'', but we're inside, so we see \'' )
                let remaining = String(interior[i...])
                #expect(remaining.hasPrefix(#"\'"#), "unescaped interior quote at \(i): \(remaining)")
                // Skip past \''
                i = interior.index(i, offsetBy: 3, limitedBy: interior.endIndex) ?? interior.endIndex
            } else {
                i = interior.index(after: i)
            }
        }
    }
}

@Test func ghosttyMustNotQuoteArgv() {
    // Ghostty's `-e` takes an argv array, never a shell string. It must NOT
    // be quoted, so a hostile hostname passes through verbatim (safely, because
    // it's argv, not a command string).
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "h;x", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    // Must be exactly ["-e", "ssh", "radnok@h;x"] - no quoting applied.
    #expect(arguments == ["-e", "ssh", "radnok@h;x"])
    // Specifically: no single quotes around the destination.
    #expect(!arguments[2].contains("'"))
}

@Test func ghosttyDoesNotEscapeBecauseArgvNeedsNoQuoting() {
    // Ghostty takes an argv array directly, so the raw value is correct there.
    let plan = launchPlan(for: .ghostty, user: "radnok", host: "h;x", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    // The raw value survives untouched because argv needs no quoting.
    #expect(arguments == ["-e", "ssh", "radnok@h;x"])
}

@Test func terminalUsesAppleScript() {
    let plan = launchPlan(for: .terminal, user: "radnok", host: "100.123.34.96", isRunning: false)
    guard case let .appleScript(source, bundleID) = plan else {
        Issue.record("expected appleScript, got \(plan)")
        return
    }
    #expect(bundleID == "com.apple.Terminal")
    #expect(source.contains("do script"))
    #expect(source.contains("ssh radnok@100.123.34.96"))
}

@Test func warpOpensAndCopiesBecauseItRefusesToSubmitInput() {
    // Warp Control deliberately provides no action that submits input.
    let plan = launchPlan(for: .warp, user: "radnok", host: "100.123.34.96", isRunning: false)
    #expect(plan == .openAndCopyToClipboard(
        bundleID: "dev.warp.Warp-Stable",
        clipboard: "ssh radnok@100.123.34.96"
    ))
}

@Test func sshCommandLineJoinsUserAndHost() {
    #expect(sshCommandLine(user: "radnok", host: "100.123.34.96") == "ssh radnok@100.123.34.96")
}

@Test func everyTerminalHasDistinctBundleIdentifier() {
    let ids = TerminalKind.allCases.map(\.bundleIdentifier)
    #expect(Set(ids).count == ids.count)
    #expect(!ids.contains(where: { $0.isEmpty }))
}

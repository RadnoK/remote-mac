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

@Test func itermEscapesShellMetacharacters() {
    // iTerm re-parses the string via `login … $SHELL -c`, so metacharacters
    // in a hostname would otherwise execute.
    let plan = launchPlan(for: .iterm, user: "radnok", host: "h; touch /tmp/pwned", isRunning: false)
    guard case let .openWithArguments(_, arguments, _) = plan else {
        Issue.record("expected openWithArguments")
        return
    }
    let arg = arguments[0]
    #expect(!arg.contains("; touch"))
    #expect(arg.contains("\\;") || arg.contains("'"))
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

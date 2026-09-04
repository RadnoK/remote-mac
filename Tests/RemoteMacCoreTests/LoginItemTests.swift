import Testing
@testable import RemoteMacCore

@Test func currentStateIsReadableWithoutCrashing() {
    // Under `swift test` there is no .app bundle, so this reports
    // .unavailable rather than trapping.
    let state = LoginItem.current
    #expect(LoginItemState.allValues.contains(state))
}

@Test func requiresApprovalIsDistinctFromDisabled() {
    // The user can revoke consent in System Settings; that is a different
    // condition from never having enabled it, and needs a different prompt.
    #expect(LoginItemState.requiresApproval != .disabled)
}

@Test func everyStateHasNonEmptyPolishLabel() {
    #expect(LoginItemState.allValues.allSatisfy { !$0.label.isEmpty })
}

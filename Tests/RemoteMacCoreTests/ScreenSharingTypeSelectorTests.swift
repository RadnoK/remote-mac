import Foundation
import Testing
@testable import RemoteMacCore

/// An Accessibility element the test can rearrange while the selector's
/// detached polling task reads it, hence the lock. `isEnabledRule` receives
/// the 0-based index of each `isEnabled` read, so a test can keep a button
/// disabled for the first N polls the way Screen Sharing greys out Continue
/// while it is still "Connecting…".
private final class FakeNode: AXNode, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextID = 0

    let id: Int
    private let lock = NSLock()
    private var _role: String?
    private var _children: [any AXNode]
    private var _isEnabledRule: (Int) -> Bool
    private var _enabledReads = 0
    private var _pressCount = 0
    private var _onPress: ((Int) -> Void)?

    init(_ role: String?, children: [any AXNode] = [],
         isEnabled: @escaping (Int) -> Bool = { _ in true }) {
        id = FakeNode.lock.withLock {
            FakeNode.nextID += 1
            return FakeNode.nextID
        }
        _role = role
        _children = children
        _isEnabledRule = isEnabled
    }

    var role: String? { lock.withLock { _role } }
    var children: [any AXNode] { lock.withLock { _children } }

    var isEnabled: Bool {
        lock.withLock {
            defer { _enabledReads += 1 }
            return _isEnabledRule(_enabledReads)
        }
    }

    var enabledReads: Int { lock.withLock { _enabledReads } }
    var pressCount: Int { lock.withLock { _pressCount } }

    /// Called with the new press count, outside the lock, so the hook may
    /// mutate a `FakeSource` (e.g. close the chooser once confirmed).
    func onPress(_ hook: @escaping (Int) -> Void) {
        lock.withLock { _onPress = hook }
    }

    @discardableResult
    func press() -> Bool {
        let (count, hook) = lock.withLock {
            _pressCount += 1
            return (_pressCount, _onPress)
        }
        hook?(count)
        return true
    }
}

private final class FakeSource: ScreenSharingWindowSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _windows: [any AXNode]

    init(_ windows: [any AXNode] = []) { _windows = windows }

    func windows() -> [any AXNode] { lock.withLock { _windows } }

    func add(_ window: any AXNode) { lock.withLock { _windows.append(window) } }

    func remove(_ window: any AXNode) {
        lock.withLock { _windows.removeAll { $0.id == window.id } }
    }
}

/// The measured Screen Sharing chooser shape: the labels live in
/// AXDescription and are localized, so the fake carries none.
private struct Chooser {
    let window: FakeNode
    let standard: FakeNode
    let highPerformance: FakeNode
    let help: FakeNode
    let cancel: FakeNode
    let confirm: FakeNode

    init(confirmEnabled: @escaping (Int) -> Bool = { _ in true }) {
        standard = FakeNode("AXRadioButton")
        highPerformance = FakeNode("AXRadioButton")
        help = FakeNode("AXButton")
        cancel = FakeNode("AXButton")
        confirm = FakeNode("AXButton", isEnabled: confirmEnabled)
        let radios = FakeNode("AXRadioGroup", children: [standard, highPerformance])
        let group = FakeNode("AXGroup", children: [
            FakeNode("AXHeading"), radios, help, cancel, confirm,
        ])
        window = FakeNode("AXWindow", children: [group, FakeNode("AXStaticText")])
    }

    /// Screen Sharing closes the chooser once Continue takes effect.
    func closes(in source: FakeSource, afterConfirmPresses presses: Int = 1) {
        confirm.onPress { [window] count in
            if count >= presses { source.remove(window) }
        }
    }
}

private let poll: Duration = .milliseconds(5)
/// For tests that must run into the deadline.
private let shortTimeout: Duration = .milliseconds(300)
/// For tests that must end because the chooser closed: generous, so a
/// loaded CI machine can never turn success into a timeout.
private let longTimeout: Duration = .seconds(10)
private let retry: Duration = .milliseconds(20)

@MainActor
private func makeSelector(_ source: FakeSource, timeout: Duration) -> AXScreenSharingTypeSelector {
    AXScreenSharingTypeSelector(source: source, pollInterval: poll, timeout: timeout,
                                confirmRetryInterval: retry)
}

// MARK: - Locator

@Test func locatorFindsNestedChooser() throws {
    let chooser = Chooser()
    let found = try #require(findTypeChooser(in: chooser.window))
    #expect(found.standard.id == chooser.standard.id)
    #expect(found.highPerformance.id == chooser.highPerformance.id)
    #expect(found.confirm.id == chooser.confirm.id)
}

@Test func locatorRejectsThreeRadios() {
    let radios = FakeNode("AXRadioGroup", children: [
        FakeNode("AXRadioButton"), FakeNode("AXRadioButton"), FakeNode("AXRadioButton"),
    ])
    let window = FakeNode("AXWindow", children: [
        FakeNode("AXGroup", children: [radios, FakeNode("AXButton"), FakeNode("AXButton")]),
    ])
    #expect(findTypeChooser(in: window) == nil)
}

@Test func locatorRejectsChooserWithFewerThanTwoButtons() {
    let radios = FakeNode("AXRadioGroup", children: [
        FakeNode("AXRadioButton"), FakeNode("AXRadioButton"),
    ])
    let window = FakeNode("AXWindow", children: [
        FakeNode("AXGroup", children: [radios, FakeNode("AXButton")]),
    ])
    #expect(findTypeChooser(in: window) == nil)
}

@Test func locatorRejectsSessionWindow() {
    let toolbar = FakeNode("AXToolbar", children: [
        FakeNode("AXButton"), FakeNode("AXButton"), FakeNode("AXButton"),
    ])
    let window = FakeNode("AXWindow", children: [
        toolbar, FakeNode("AXButton"), FakeNode("AXButton"), FakeNode("AXScrollArea"),
    ])
    #expect(findTypeChooser(in: window) == nil)
}

// MARK: - Selector

@MainActor
@Test func pressesHighPerformanceThenConfirm() async {
    let source = FakeSource()
    let chooser = Chooser()
    chooser.closes(in: source)
    let selector = makeSelector(source, timeout: longTimeout)

    await selector.select(.highPerformance) { source.add(chooser.window) }.value

    #expect(chooser.highPerformance.pressCount == 1)
    #expect(chooser.standard.pressCount == 0)
    #expect(chooser.confirm.pressCount == 1)
    #expect(chooser.cancel.pressCount == 0)
    #expect(chooser.help.pressCount == 0)
}

@MainActor
@Test func pressesStandardForStandard() async {
    let source = FakeSource()
    let chooser = Chooser()
    chooser.closes(in: source)
    let selector = makeSelector(source, timeout: longTimeout)

    await selector.select(.standard) { source.add(chooser.window) }.value

    #expect(chooser.standard.pressCount == 1)
    #expect(chooser.highPerformance.pressCount == 0)
    #expect(chooser.confirm.pressCount == 1)
}

@MainActor
@Test func waitsForConfirmToEnable() async {
    let source = FakeSource()
    let chooser = Chooser(confirmEnabled: { $0 >= 5 })
    chooser.closes(in: source)
    let selector = makeSelector(source, timeout: longTimeout)

    await selector.select(.highPerformance) { source.add(chooser.window) }.value

    #expect(chooser.confirm.enabledReads == 6)
    #expect(chooser.confirm.pressCount == 1)
    #expect(chooser.highPerformance.pressCount == 1)
}

/// The `AXEnabled` flag is not trustworthy on this dialog — Continue reports
/// enabled while it is greyed out — so one press can be swallowed. The
/// selector keeps pressing until the chooser actually goes away.
@MainActor
@Test func repressesConfirmUntilChooserCloses() async {
    let source = FakeSource()
    let chooser = Chooser()
    chooser.closes(in: source, afterConfirmPresses: 2)
    let selector = makeSelector(source, timeout: longTimeout)

    let start = ContinuousClock.now
    await selector.select(.highPerformance) { source.add(chooser.window) }.value

    #expect(chooser.confirm.pressCount == 2)
    #expect(chooser.highPerformance.pressCount == 1)
    #expect(ContinuousClock.now - start < longTimeout / 2)
}

@MainActor
@Test func ignoresChooserThatExistedBeforeOpen() async {
    let chooser = Chooser()
    let source = FakeSource([chooser.window])
    let selector = makeSelector(source, timeout: shortTimeout)

    await selector.select(.highPerformance) {}.value

    #expect(chooser.standard.pressCount == 0)
    #expect(chooser.highPerformance.pressCount == 0)
    #expect(chooser.confirm.pressCount == 0)
}

@MainActor
@Test func secondSelectCancelsFirst() async {
    let source = FakeSource()
    let first = Chooser(confirmEnabled: { _ in false })
    let second = Chooser()
    second.closes(in: source)
    let selector = makeSelector(source, timeout: longTimeout)

    let firstTask = selector.select(.highPerformance) { source.add(first.window) }
    // Let the first watcher find its chooser and start waiting on confirm.
    let waitStart = ContinuousClock.now
    while first.confirm.enabledReads == 0, ContinuousClock.now - waitStart < .seconds(5) {
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(first.confirm.enabledReads > 0)

    let start = ContinuousClock.now
    let secondTask = selector.select(.standard) { source.add(second.window) }
    await firstTask.value
    await secondTask.value

    #expect(ContinuousClock.now - start < longTimeout / 2)
    #expect(first.highPerformance.pressCount == 1)
    #expect(first.confirm.pressCount == 0)
    #expect(second.standard.pressCount == 1)
    #expect(second.confirm.pressCount == 1)
}

@MainActor
@Test func confirmNeverEnablingTimesOut() async {
    let source = FakeSource()
    let chooser = Chooser(confirmEnabled: { _ in false })
    let selector = makeSelector(source, timeout: shortTimeout)

    let start = ContinuousClock.now
    await selector.select(.highPerformance) { source.add(chooser.window) }.value
    let elapsed = ContinuousClock.now - start

    #expect(chooser.highPerformance.pressCount == 1)
    #expect(chooser.confirm.pressCount == 0)
    #expect(elapsed >= shortTimeout)
    #expect(elapsed < shortTimeout + .seconds(3))
}

@MainActor
@Test func openIsCalledExactlyOnce() async {
    let source = FakeSource()
    let chooser = Chooser()
    chooser.closes(in: source)
    let selector = makeSelector(source, timeout: longTimeout)

    var opens = 0
    await selector.select(.highPerformance) {
        opens += 1
        source.add(chooser.window)
    }.value

    #expect(opens == 1)
}

@MainActor
@Test func cancelStopsTheWatcher() async {
    let source = FakeSource()
    let selector = makeSelector(source, timeout: longTimeout)
    let start = ContinuousClock.now

    let task = selector.select(.highPerformance) {}
    selector.cancel()
    await task.value

    #expect(ContinuousClock.now - start < longTimeout / 2)
}

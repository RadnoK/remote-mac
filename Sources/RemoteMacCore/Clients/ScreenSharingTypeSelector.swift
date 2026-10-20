import Foundation

/// Answers Screen Sharing's Standard / High Performance chooser, which no
/// setting can skip on Apple-silicon pairs.
@MainActor
public protocol ScreenSharingTypeSelecting {
    /// `open` is called exactly once, after the selector has noted which
    /// windows already exist, so only a chooser this connection produced is
    /// ever answered. The returned task ends when the chooser closes, the
    /// watch times out, or it is cancelled.
    @discardableResult
    func select(_ type: ScreenSharingType, opening open: () -> Void) -> Task<Void, Never>
    func cancel()
}

/// Watches Screen Sharing through the Accessibility API. Every failure —
/// no permission, no chooser (Intel pairs never show one), a layout this
/// build does not recognise — simply runs out the timeout, leaving the
/// chooser to the user as before.
@MainActor
public final class AXScreenSharingTypeSelector: ScreenSharingTypeSelecting {
    private let source: any ScreenSharingWindowSource
    private let pollInterval: Duration
    private let timeout: Duration
    private let confirmRetryInterval: Duration
    private var task: Task<Void, Never>?

    /// `confirmRetryInterval` spaces repeated presses of the confirm button:
    /// Continue reports `AXEnabled` from the first poll even while the
    /// dialog still shows "Connecting…" with it greyed out, so an early
    /// press can be swallowed and is retried until the chooser closes.
    public init(
        source: any ScreenSharingWindowSource = AXScreenSharingWindowSource(),
        pollInterval: Duration = .milliseconds(100),
        timeout: Duration = .seconds(20),
        confirmRetryInterval: Duration = .milliseconds(500)
    ) {
        self.source = source
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.confirmRetryInterval = confirmRetryInterval
    }

    @discardableResult
    public func select(_ type: ScreenSharingType, opening open: () -> Void) -> Task<Void, Never> {
        cancel()
        let existing = Set(source.windows().map(\.id))
        open()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        // Detached so the Accessibility round trips, which block until
        // Screen Sharing answers, never run on the main actor.
        let task = Task.detached { [source, pollInterval, confirmRetryInterval] in
            await Self.answer(
                type, source: source, ignoring: existing, deadline: deadline,
                pollInterval: pollInterval, confirmRetryInterval: confirmRetryInterval)
        }
        self.task = task
        return task
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private nonisolated static func answer(
        _ type: ScreenSharingType,
        source: any ScreenSharingWindowSource,
        ignoring existing: Set<Int>,
        deadline: ContinuousClock.Instant,
        pollInterval: Duration,
        confirmRetryInterval: Duration
    ) async {
        var found: (windowID: Int, chooser: TypeChooser)?
        while found == nil {
            guard !Task.isCancelled else { return }
            found = source.windows().lazy
                .filter { !existing.contains($0.id) }
                .compactMap { window in findTypeChooser(in: window).map { (window.id, $0) } }
                .first
            if found == nil {
                guard await sleep(for: pollInterval, before: deadline) else { return }
            }
        }
        guard let (windowID, chooser) = found else { return }

        switch type {
        case .standard: chooser.standard.press()
        case .highPerformance: chooser.highPerformance.press()
        }

        // Success is the chooser going away, not a press returning `.success`.
        while !Task.isCancelled {
            guard source.windows().contains(where: { $0.id == windowID }) else { return }
            let interval: Duration
            if chooser.confirm.isEnabled {
                chooser.confirm.press()
                interval = confirmRetryInterval
            } else {
                interval = pollInterval
            }
            guard await sleep(for: interval, before: deadline) else { return }
        }
    }

    /// Sleeps for `interval`, clipped to the deadline. Returns `false` when
    /// the deadline has passed or the task was cancelled.
    private nonisolated static func sleep(
        for interval: Duration, before deadline: ContinuousClock.Instant
    ) async -> Bool {
        let remaining = deadline - ContinuousClock.now
        guard remaining > .zero else { return false }
        do {
            try await Task.sleep(for: min(interval, remaining))
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}

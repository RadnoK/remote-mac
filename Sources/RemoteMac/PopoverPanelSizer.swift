import AppKit
import SwiftUI

/// Snaps the menu bar panel back to its content's height, and gives it a
/// translucent background.
///
/// `MenuBarExtra(.window)` grows the panel when tall content appears but
/// never shrinks it again (observed on macOS 26): reopened on the short
/// "no machines" view, the panel keeps the tallest frame it has ever shown
/// and floats the content in the leftover space. This view sits in the
/// popover's background and re-fits the window whenever it lands in one or
/// the content case changes.
///
/// Ported from RouterMenu's `PopoverPanelSizer` — the bug, and the fix, are
/// both specific to `MenuBarExtra(.window)`, not to this app.
struct PopoverPanelSizer: NSViewRepresentable {
    /// Changes when the popover switches content case, so `updateNSView`
    /// fires and re-fits a panel that is already on screen.
    let stateKey: String

    /// The corrected window frame, or nil when the current one already fits.
    /// The top edge stays anchored — AppKit measures `origin.y` from the
    /// bottom of the screen, so the origin absorbs the height delta and the
    /// panel keeps hanging from the menu bar. Sub-point deltas are ignored,
    /// or every layout pass would jiggle the window.
    nonisolated static func fittedFrame(for frame: NSRect,
                                        fittingHeight: CGFloat) -> NSRect? {
        guard fittingHeight > 0 else { return nil }
        let delta = fittingHeight - frame.height
        guard abs(delta) > 1 else { return nil }
        var fitted = frame
        fitted.origin.y -= delta
        fitted.size.height = fittingHeight
        return fitted
    }

    func makeNSView(context: Context) -> TrackerView { TrackerView() }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.refit()
    }

    final class TrackerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installBackdrop()
            refit()
        }

        /// Clears the panel's opaque fill and slots an `NSVisualEffectView`
        /// under the content. `.menu` is the thinnest of the popover
        /// materials — the desktop reads through it, which is the point.
        ///
        /// Idempotent: `viewDidMoveToWindow` fires again whenever the panel
        /// is rebuilt, and a second effect view would stack another wash of
        /// tint over the first.
        private func installBackdrop() {
            guard let window = self.window,
                  let content = window.contentView else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            guard !content.subviews.contains(where: { $0 is Backdrop }) else { return }
            let backdrop = Backdrop()
            backdrop.material = .menu
            backdrop.blendingMode = .behindWindow
            // .active, not .followsWindowActiveState: the panel resigns key
            // as soon as the user clicks another app, and a backdrop that
            // goes solid grey on the way out is the bug we came to fix.
            backdrop.state = .active
            backdrop.autoresizingMask = [.width, .height]
            backdrop.frame = content.bounds
            // Clipped to the panel's own corners — clearing the window drops
            // the system's rounding, leaving the material square at the tips.
            backdrop.wantsLayer = true
            backdrop.layer?.cornerRadius = Self.cornerRadius
            backdrop.layer?.cornerCurve = .continuous
            backdrop.layer?.masksToBounds = true
            content.addSubview(backdrop, positioned: .below, relativeTo: nil)
        }

        /// Matches the panel rounding `MenuBarExtra(.window)` draws itself.
        static let cornerRadius: CGFloat = 11

        /// A marker class, so the idempotence check cannot mistake some other
        /// effect view SwiftUI may park in the panel for ours.
        final class Backdrop: NSVisualEffectView {}

        func refit() {
            // After the in-flight layout pass — fittingSize is stale before it.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window,
                      let content = window.contentView,
                      let frame = PopoverPanelSizer.fittedFrame(
                          for: window.frame,
                          fittingHeight: content.fittingSize.height) else { return }
                window.setFrame(frame, display: true)
            }
        }
    }
}

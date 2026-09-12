import SwiftUI
import AppKit

/// Why AppKit: SwiftUI has no scroll-wheel gesture on any platform — the
/// gesture catalog is taps, long-presses, drags, magnify, rotate and spatial
/// events — and trackpad two-finger pan is table stakes for an infinite canvas. (SALVAGE-COPY of CanvasScrollBridge — survives the Drawing tear-out.)
/// This is the second deliberate AppKit exception (MarkdownSourceEditor is the
/// first).
///
/// Mechanism: a LOCAL NSEvent monitor, not a `scrollWheel(with:)` override.
/// The override was tried first and never fired — SwiftUI's hosting view
/// claims scroll routing before a background representable's NSView sees the
/// event. The monitor observes events pre-dispatch, so hosting-view routing
/// cannot starve it. The monitor's app-global reach is scoped back down by the
/// two checks a view-based design would have gotten free:
///   * `event.window === view.window` — a second session window's canvas
///     never sees this window's scrolls;
///   * the event location converted into the view's own bounds — scrolls over
///     the sidebar List or the prompt editor pass through untouched
///     (returning the event unconsumed preserves normal dispatch).
/// Lifetime is owned by the NSView: installed on window attach, removed on
/// window detach AND deinit, so momentum deltas can't fire into a dead closure
/// after the pane is torn down.
struct DiagramScrollBridge: NSViewRepresentable {
    /// Reference-typed sink: closures are swapped in place, so `updateNSView`
    /// never rebuilds the view and can never feed an observation loop.
    @MainActor
    final class Sink {
        var onPan: (CGSize) -> Void = { _ in }
        /// (factor, anchor in view coordinates, top-left origin)
        var onZoom: (CGFloat, CGPoint) -> Void = { _, _ in }
    }
    let sink: Sink

    func makeNSView(context: Context) -> ScrollCatcher { ScrollCatcher(sink: sink) }
    func updateNSView(_ nsView: ScrollCatcher, context: Context) { nsView.sink = sink }

    final class ScrollCatcher: NSView {
        var sink: Sink
        private var monitor: Any?

        init(sink: Sink) {
            self.sink = sink
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unused") }

        /// v0 ships no keyboard handling — a focusable view here would join the
        /// key-view loop and steal arrow keys from the sidebar List. Flipping
        /// this to true and adding `keyDown` is the entire v1 tool-shortcut seam.
        override var acceptsFirstResponder: Bool { false }
        override var isFlipped: Bool { true }   // match SwiftUI's top-left origin

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        /// Returns nil when consumed, the event untouched when it isn't ours.
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local) else { return event }

            // Mouse wheels report LINES; trackpads report points. Without the
            // scale a wheel notch pans one pixel. `scrollingDeltaX/Y` arrive
            // with the user's natural-scrolling preference ALREADY applied —
            // `isDirectionInvertedFromDevice` merely reports that it happened
            // and must never be used as a correction, or the default
            // configuration pans backwards.
            let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            var dx = event.scrollingDeltaX * unit
            var dy = event.scrollingDeltaY * unit
            // Shift+wheel means "the other axis" on a device with no X deltas.
            if event.modifierFlags.contains(.shift), dx == 0 { swap(&dx, &dy) }

            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                // A mouse has no pinch gesture — modifier-scroll is how mouse
                // users zoom at all. Momentum-phase zoom feels broken; drop it.
                guard event.momentumPhase == [] else { return nil }
                sink.onZoom(exp(dy * 0.01), local)
            } else {
                sink.onPan(CGSize(width: dx, height: dy))
            }
            return nil
        }
    }
}

import AppKit
import SwiftUI
import Combine

/// Owns the notch window + view model and computes screen geometry.
///
/// Key design choice: the window is a FIXED size (a canvas big enough for the
/// expanded card, centered under the physical notch) and is never resized while
/// hovering. Only the black notch shape *inside* the window animates between
/// collapsed and expanded. This avoids the AppKit-frame / SwiftUI-layout race
/// that made the collapsed content jitter during the open/close animation.
@MainActor
final class NotchController {
    private let viewModel = NotchViewModel()
    private var window: NotchWindow?
    private weak var hostingView: PassthroughHostingView<NotchView>?
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    // Fixed window canvas. Generous enough to hold the expanded card; the
    // collapsed notch lives at the top-center of this same canvas.
    private let canvasWidth: CGFloat = 480
    private let canvasHeight: CGFloat = 240

    func start() {
        buildWindow()
        viewModel.start()

        // When expansion flips, refresh the hit region so clicks/hover only
        // land on the currently-visible shape. No window resize happens.
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.hostingView?.needsLayout = true
            }
            .store(in: &cancellables)
    }

    func stop() {
        viewModel.stop()
        removeMouseTracking()
        window?.orderOut(nil)
        window = nil
    }

    func screenParametersChanged() {
        layout()
    }

    // MARK: - Settings (exposed to the status-bar menu)

    var isThemingEnabled: Bool { viewModel.themingEnabled }
    func setThemingEnabled(_ on: Bool) { viewModel.themingEnabled = on }

    /// Screens available + which one currently hosts the notch.
    var availableScreens: [NSScreen] { NSScreen.screens }
    var hostScreenID: UInt32 { NotchMetrics.current().screen.displayID }
    /// 0 = automatic.
    var preferredScreenID: UInt32 { ScreenPreference.preferredDisplayID }
    func setPreferredScreen(_ id: UInt32) {
        ScreenPreference.preferredDisplayID = id
        layout()
    }

    // MARK: - Window

    private func buildWindow() {
        applyMetrics()

        let panel = NotchWindow(contentRect: canvasFrame())
        let host = PassthroughHostingView(rootView: NotchView(viewModel: viewModel))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.hitRegion = { [weak self] in self?.visibleNotchRect() ?? .zero }

        panel.contentView = host
        panel.orderFrontRegardless()

        self.window = panel
        self.hostingView = host

        installMouseTracking()
        updateState()
    }

    // MARK: - Mouse pass-through

    /// Watch the cursor (both inside and outside our app) and let the panel
    /// swallow events ONLY while the pointer is over the visible notch shape.
    /// Everywhere else the window ignores the mouse entirely, so clicks land on
    /// the desktop / windows underneath. Relying on `hitTest` alone is unreliable
    /// for a background, non-activating panel — this is the robust approach.
    private func installMouseTracking() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.updateState() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: handler
        )
        // The local monitor must return the event so normal delivery continues
        // (except scroll events we consume to drive the volume).
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .scrollWheel {
                return self.handleScroll(event) ? nil : event
            }
            self.updateState()
            return event
        }
    }

    /// Scrolling over the visible notch adjusts the active source's volume.
    /// Returns true if the event was handled (and should be swallowed).
    private func handleScroll(_ event: NSEvent) -> Bool {
        let cursor = NSEvent.mouseLocation
        guard cursorInside(notchRectInScreen(expanded: viewModel.isExpanded), cursor) else {
            return false
        }
        // Normalise to physical wheel direction (up = louder) regardless of the
        // "natural scrolling" setting.
        var dy = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { dy = -dy }
        guard dy != 0 else { return true }
        viewModel.adjustVolume(by: dy * 0.005)
        return true
    }

    private func removeMouseTracking() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    /// Single source of truth driven by the real cursor position. Decides both
    /// expansion and mouse pass-through, with hysteresis so the open/close zones
    /// don't fight each other:
    ///   - while collapsed, expand only when the cursor is over the *tight*
    ///     notch strip (so it doesn't pop open from far away);
    ///   - while expanded, stay open until the cursor leaves the *whole* card.
    /// `ignoresMouseEvents` mirrors that visible region, so clicks pass straight
    /// through to the desktop everywhere else.
    private func updateState() {
        guard let window else { return }
        let cursor = NSEvent.mouseLocation

        let shouldExpand: Bool
        if viewModel.isExpanded {
            shouldExpand = cursorInside(notchRectInScreen(expanded: true), cursor)
        } else {
            shouldExpand = cursorInside(notchRectInScreen(expanded: false), cursor)
        }
        if viewModel.isExpanded != shouldExpand {
            withAnimation(.easeOut(duration: 0.28)) {
                viewModel.isExpanded = shouldExpand
            }
        }

        // Receive events only over the currently-visible shape.
        let inside = cursorInside(notchRectInScreen(expanded: shouldExpand), cursor)
        if window.ignoresMouseEvents == inside {
            window.ignoresMouseEvents = !inside
        }
    }

    private func layout() {
        applyMetrics()
        window?.setFrame(canvasFrame(), display: true)
    }

    private func applyMetrics() {
        let metrics = NotchMetrics.current()
        viewModel.collapsedSize = CGSize(width: metrics.collapsedWidth, height: metrics.height)
        viewModel.expandedSize = CGSize(width: min(440, canvasWidth - 20), height: 202)
    }

    /// The fixed window frame: full canvas, centered horizontally under the
    /// notch, pinned to the very top of the screen.
    private func canvasFrame() -> NSRect {
        let screen = NotchMetrics.current().screen.frame
        return NSRect(
            x: screen.midX - canvasWidth / 2,
            y: screen.maxY - canvasHeight,
            width: canvasWidth,
            height: canvasHeight
        )
    }

    /// The currently-visible notch rectangle inside the window (bottom-left
    /// origin), used for mouse hit-testing. Matches what SwiftUI draws.
    private func visibleNotchRect() -> NSRect {
        let w = viewModel.isExpanded ? viewModel.expandedSize.width : viewModel.collapsedSize.width
        let h = viewModel.isExpanded ? viewModel.expandedSize.height : viewModel.collapsedSize.height
        return NSRect(
            x: (canvasWidth - w) / 2,
            y: canvasHeight - h,   // top-aligned
            width: w,
            height: h
        )
    }

    /// Whether the cursor is over the notch region, with all edges inclusive.
    /// `NSRect.contains` is half-open and drops the cursor at the very top edge
    /// (`y == maxY`), which made the widget collapse when you reached the screen
    /// top. We include `maxY` to fix that — but keep it bounded (not unbounded)
    /// so a second display arranged *above* the notch screen, overlapping the
    /// notch's horizontal span, never triggers expansion from the other screen.
    private func cursorInside(_ rect: NSRect, _ p: NSPoint) -> Bool {
        p.x >= rect.minX && p.x <= rect.maxX && p.y >= rect.minY && p.y <= rect.maxY
    }

    /// The notch rectangle (collapsed strip or expanded card) in screen
    /// coordinates (bottom-left origin), used to decide whether the cursor is
    /// over the interactive region.
    private func notchRectInScreen(expanded: Bool) -> NSRect {
        let w = expanded ? viewModel.expandedSize.width : viewModel.collapsedSize.width
        let h = expanded ? viewModel.expandedSize.height : viewModel.collapsedSize.height
        let local = NSRect(
            x: (canvasWidth - w) / 2,
            y: canvasHeight - h,   // top-aligned
            width: w,
            height: h
        )
        let origin = window?.frame.origin ?? .zero
        return local.offsetBy(dx: origin.x, dy: origin.y)
    }
}

/// Resolved geometry for the screen that hosts the notch widget.
struct NotchMetrics {
    let screen: NSScreen
    /// Height of the notch strip (menu-bar height on notched Macs).
    let height: CGFloat
    /// Collapsed widget width (physical notch width, or a synthetic value).
    let collapsedWidth: CGFloat

    static func current() -> NotchMetrics {
        // A user-picked screen wins; else the built-in display with a notch.
        let preferred = ScreenPreference.preferredDisplayID
        let chosen = preferred != 0 ? NSScreen.screens.first { $0.displayID == preferred } : nil
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let screen = chosen ?? notched ?? NSScreen.main ?? NSScreen.screens.first!

        let top = screen.safeAreaInsets.top
        if top > 0, let width = physicalNotchWidth(of: screen) {
            return NotchMetrics(screen: screen, height: top, collapsedWidth: width)
        }

        // No physical notch: synthesize a tidy widget at the top center.
        let menuHeight = NSStatusBar.system.thickness
        return NotchMetrics(screen: screen, height: max(menuHeight, 24), collapsedWidth: 200)
    }

    /// Width of the physical notch, derived from the auxiliary top areas
    /// that flank it.
    private static func physicalNotchWidth(of screen: NSScreen) -> CGFloat? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        return width > 0 ? width : nil
    }
}

extension NSScreen {
    /// The CoreGraphics display ID — stable enough to remember a chosen screen.
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Persisted choice of which display hosts the notch (0 = automatic).
enum ScreenPreference {
    private static let key = "preferredDisplayID"
    static var preferredDisplayID: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: key)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: key) }
    }
}

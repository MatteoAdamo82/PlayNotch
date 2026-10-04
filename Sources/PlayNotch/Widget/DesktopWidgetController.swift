import AppKit
import SwiftUI

/// Shows/hides the floating desktop widget and remembers its position and
/// on/off state. Shares the notch's view model, so both reflect the same
/// playback with a single media poll.
@MainActor
final class DesktopWidgetController {
    private let viewModel: NotchViewModel
    private var window: DesktopWidgetWindow?

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    /// Restore the widget on launch if it was left enabled.
    func restore() {
        if WidgetPreference.enabled { show() }
    }

    var isVisible: Bool { window != nil }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard window == nil else { return }
        WidgetPreference.enabled = true

        let host = NSHostingView(rootView: DesktopWidgetView(viewModel: viewModel))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        // The card has a fixed intrinsic size; ask it once and pin the window
        // to it so the window never resizes as the track/state changes.
        let size = host.fittingSize

        let panel = DesktopWidgetWindow(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = host
        panel.setFrame(NSRect(origin: initialOrigin(for: size), size: size), display: true)
        panel.orderFrontRegardless()

        // Persist position whenever the user drags the card.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved(_:)),
            name: NSWindow.didMoveNotification, object: panel
        )

        self.window = panel
    }

    func hide() {
        WidgetPreference.enabled = false
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
            window.orderOut(nil)
        }
        window = nil
    }

    @objc private func windowMoved(_ note: Notification) {
        guard let window else { return }
        WidgetPreference.origin = window.frame.origin
    }

    /// Saved position, or a sensible default near the top-right of the main
    /// screen if there's none yet (or the saved one is off-screen).
    private func initialOrigin(for size: NSSize) -> NSPoint {
        if let saved = WidgetPreference.origin,
           NSScreen.screens.contains(where: { $0.frame.intersects(NSRect(origin: saved, size: size)) }) {
            return saved
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24)
    }
}

/// Persisted widget on/off state and last position.
enum WidgetPreference {
    private static let enabledKey = "desktopWidgetEnabled"
    private static let xKey = "desktopWidgetX"
    private static let yKey = "desktopWidgetY"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var origin: NSPoint? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: xKey) != nil, d.object(forKey: yKey) != nil else { return nil }
            return NSPoint(x: d.double(forKey: xKey), y: d.double(forKey: yKey))
        }
        set {
            let d = UserDefaults.standard
            if let p = newValue {
                d.set(p.x, forKey: xKey)
                d.set(p.y, forKey: yKey)
            }
        }
    }
}

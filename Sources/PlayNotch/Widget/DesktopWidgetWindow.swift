import AppKit

/// A movable, non-activating panel that hosts the floating desktop widget.
///
/// Unlike the notch window (pinned, click-through outside the shape), this one
/// is a normal draggable card: it floats above regular windows, can be moved
/// anywhere, and remembers its position — but still never steals key focus from
/// the app you're working in.
final class DesktopWidgetWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = false
        // Sit on the desktop, behind normal app windows (like a real desktop
        // widget) instead of floating above everything.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // The whole card is draggable by its background (see CardDragging).
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

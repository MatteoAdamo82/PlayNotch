import AppKit

/// A borderless, non-activating panel that floats over everything (including
/// the menu bar) and never steals focus from the app you're working in.
final class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar + 1
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    // Allow the panel to receive clicks (transport buttons) without ever
    // becoming the key/main window of the system.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

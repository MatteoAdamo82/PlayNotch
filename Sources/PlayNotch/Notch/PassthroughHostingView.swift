import AppKit
import SwiftUI

/// A hosting view for a fixed-size, mostly-transparent notch window.
///
/// The window stays a constant size (a canvas big enough for the expanded
/// card) so the SwiftUI layout never reflows mid-animation — only the black
/// notch shape inside it grows and shrinks. The downside of a fixed window is
/// that its transparent regions would otherwise swallow mouse clicks meant for
/// whatever is underneath (menu bar, desktop). We fix that here: `hitTest`
/// returns nil for any point outside the currently-visible notch rectangle, so
/// those clicks pass straight through.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// The currently-visible notch rectangle, in this view's coordinate space
    /// (bottom-left origin). Supplied by the controller from the view model.
    var hitRegion: () -> NSRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitRegion().contains(point) else { return nil }
        return super.hitTest(point)
    }

    // The panel is a non-activating, background (LSUIElement) window that can't
    // become key. Without this, AppKit treats the first click on the notch as a
    // window-ordering "first mouse" and swallows it instead of delivering it to
    // the SwiftUI transport buttons — so the controls appear dead. Accepting
    // first mouse routes the click straight to the control under the cursor,
    // without ever activating the window or stealing focus from your work.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

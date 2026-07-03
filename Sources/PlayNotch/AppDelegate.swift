import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var widgetController: DesktopWidgetController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One shared view model → one media poll feeding both the notch and the
        // optional floating desktop widget.
        let viewModel = NotchViewModel()

        let controller = NotchController(viewModel: viewModel)
        controller.start()
        notchController = controller

        let widget = DesktopWidgetController(viewModel: viewModel)
        widget.restore()
        widgetController = widget

        statusItemController = StatusItemController(notch: controller, widget: widget)

        // Reposition / rebuild the notch when the screen layout changes
        // (display connected/disconnected, resolution change, etc.).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notchController?.screenParametersChanged()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
    }
}

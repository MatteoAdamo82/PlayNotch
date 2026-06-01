import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController()
        controller.start()
        notchController = controller
        statusItemController = StatusItemController(notch: controller)

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

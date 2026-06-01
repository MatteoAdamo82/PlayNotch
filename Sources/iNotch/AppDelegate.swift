import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notchController = NotchController()
        notchController?.start()

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

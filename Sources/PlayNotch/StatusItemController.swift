import AppKit
import ServiceManagement

/// The menu-bar status item: PlayNotch's home for settings and quick actions.
/// PlayNotch is an agent app (no Dock icon), so this is the main way to reach
/// launch-at-login, theming and quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var notch: NotchController?

    init(notch: NotchController) {
        self.notch = notch
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "PlayNotch")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuild the menu each time it opens so toggles reflect the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "PlayNotch", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        let theme = NSMenuItem(title: "Theme from Artwork", action: #selector(toggleTheming), keyEquivalent: "")
        theme.target = self
        theme.state = (notch?.isThemingEnabled ?? true) ? .on : .off
        menu.addItem(theme)

        menu.addItem(.separator())

        let automation = NSMenuItem(title: "Open Automation Settings…", action: #selector(openAutomationSettings), keyEquivalent: "")
        automation.target = self
        menu.addItem(automation)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit PlayNotch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentError(error, title: "Couldn't change Launch at Login")
        }
    }

    @objc private func toggleTheming() {
        guard let notch else { return }
        notch.setThemingEnabled(!notch.isThemingEnabled)
    }

    @objc private func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

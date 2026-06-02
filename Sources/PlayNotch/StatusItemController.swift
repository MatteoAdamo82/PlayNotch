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

        if let notch {
            let screensItem = NSMenuItem(title: "Show on Screen", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let preferred = notch.preferredScreenID

            let auto = NSMenuItem(title: "Automatic", action: #selector(pickScreen(_:)), keyEquivalent: "")
            auto.target = self
            auto.representedObject = NSNumber(value: UInt32(0))
            auto.state = (preferred == 0) ? .on : .off
            submenu.addItem(auto)
            submenu.addItem(.separator())

            for screen in notch.availableScreens {
                let id = screen.displayID
                let item = NSMenuItem(title: screen.localizedName, action: #selector(pickScreen(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: id)
                // Tick the chosen screen, or the actual host when on Automatic.
                item.state = (preferred == id || (preferred == 0 && notch.hostScreenID == id)) ? .on : .off
                submenu.addItem(item)
            }
            screensItem.submenu = submenu
            menu.addItem(screensItem)
        }

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

    @objc private func pickScreen(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        notch?.setPreferredScreen(id)
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

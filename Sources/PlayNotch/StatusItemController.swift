import AppKit
import ServiceManagement

/// The menu-bar status item: PlayNotch's home for settings and quick actions.
/// PlayNotch is an agent app (no Dock icon), so this is the main way to reach
/// launch-at-login, theming and quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var notch: NotchController?
    private weak var widget: DesktopWidgetController?

    init(notch: NotchController, widget: DesktopWidgetController) {
        self.notch = notch
        self.widget = widget
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

        let bg = NSMenuItem(title: "Blurred Artwork Background", action: #selector(toggleArtworkBackground), keyEquivalent: "")
        bg.target = self
        bg.state = (notch?.isArtworkBackgroundEnabled ?? false) ? .on : .off
        menu.addItem(bg)

        let cc = NSMenuItem(title: "Show Quick Toggles", action: #selector(toggleControlCenter), keyEquivalent: "")
        cc.target = self
        cc.state = (notch?.isControlCenterShown ?? true) ? .on : .off
        menu.addItem(cc)

        let widgetItem = NSMenuItem(title: "Desktop Widget", action: #selector(toggleWidget), keyEquivalent: "")
        widgetItem.target = self
        widgetItem.state = (widget?.isVisible ?? false) ? .on : .off
        menu.addItem(widgetItem)

        let sizeItem = NSMenuItem(title: "Notch Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let current = notch?.sizeScale ?? 1.0
        for (title, scale) in [("Compact", 0.9), ("Default", 1.0), ("Large", 1.12)] {
            let item = NSMenuItem(title: title, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: scale)
            item.state = (abs(current - scale) < 0.001) ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

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

    @objc private func toggleArtworkBackground() {
        guard let notch else { return }
        notch.setArtworkBackgroundEnabled(!notch.isArtworkBackgroundEnabled)
    }

    @objc private func toggleControlCenter() {
        guard let notch else { return }
        notch.setControlCenterShown(!notch.isControlCenterShown)
    }

    @objc private func toggleWidget() {
        widget?.toggle()
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let s = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        notch?.setSizeScale(s)
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

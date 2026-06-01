import AppKit

// iNotch runs as an "agent" app: no Dock icon, no menu bar entry.
// The Info.plist sets LSUIElement, but we also enforce .accessory here
// so it behaves correctly even when launched from the raw binary.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()

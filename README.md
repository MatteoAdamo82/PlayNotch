# iNotch

An **interactive macOS notch** with a built-in music controller for
**Apple Music**, **Spotify** and **YouTube Music**. Inspired by
*Notch Dock: Control Center*.

Move the mouse over the notch (the black strip at the top center of the screen)
and it expands into a card with artwork, title, artist, a scrubbable progress
bar, a volume slider, and the controls ⏮ previous · ⏯ play/pause · ⏭ next.
It automatically picks whichever app is currently playing.

---

## Requirements

- **macOS 14** or later (tested on macOS 26).
- **Swift 6 toolchain** (Apple's Command Line Tools are enough — **Xcode is not
  required**). Check with:
  ```bash
  swift --version
  ```
  If missing, install the tools with `xcode-select --install`.

---

## Quick start

From the project folder:

```bash
./scripts/build_app.sh --run
```

This command:
1. builds in *release*,
2. creates the `build/iNotch.app` bundle,
3. kills any running instance and launches the app.

The notch appears at the top. **There is no Dock icon**: iNotch runs as a
background (agent) app.

### Other useful commands

```bash
swift build -c release      # just compile, without building the .app
./scripts/build_app.sh      # build the .app but don't launch it
```

### Quitting the app

Since there's no Dock icon, quit it from the terminal:

```bash
pkill -f "iNotch.app/Contents/MacOS"
```

---

## Permissions (one-time setup)

iNotch reads and controls the players through system automation. On the **first
command** macOS will ask for authorization: click **OK**. If you denied it,
re-enable it under:

**System Settings → Privacy & Security → Automation** → enable iNotch for
Music / Spotify / your browser.

### YouTube Music only

YT Music has no automation interface of its own, so iNotch drives the
**browser tab** where `music.youtube.com` is open. You need to enable the
JavaScript permission once:

- **Safari**: *Develop → "Allow JavaScript from Apple Events"* menu
  (if you don't see the Develop menu: *Settings → Advanced → "Show Develop
  menu"*).
- **Chrome / Brave / Edge / Arc**: *View → Developer → "Allow JavaScript from
  Apple Events"* menu.

Supported browsers for YT Music: Chrome, Brave, Edge, Arc, Safari.

---

## How it works

| App           | How it's read / controlled                            |
|---------------|--------------------------------------------------------|
| Apple Music   | AppleScript to `Music.app` (artwork included)          |
| Spotify       | AppleScript to `Spotify.app` (artwork via URL)         |
| YouTube Music | JavaScript injected into the browser tab               |

State is refreshed every second. The playback position advances smoothly
between polls via local interpolation, so the progress bar never stutters. If
multiple players are active, the one currently playing wins.

---

## Features

- Hover-to-expand notch with collapsed strip and expanded card.
- Now-playing artwork, title, artist, and source.
- Transport controls: previous / play-pause / next.
- **Scrubbable progress bar** with elapsed / total time (drag to seek).
- **Volume control**: scroll over the notch to adjust, or drag the volume
  slider.
- Click-through everywhere outside the visible notch shape (the desktop and
  windows underneath stay fully clickable).

---

## Project structure

```
Sources/iNotch/
  main.swift              agent app (.accessory, no Dock)
  AppDelegate.swift       startup + reacting to screen changes
  Media/
    NowPlaying.swift      data model + MediaSource protocol
    AppleScriptRunner     NSAppleScript helper
    AppleMusicSource      Music.app
    SpotifySource         Spotify.app
    YouTubeMusicSource    browser-tab control
    MediaController       picks the active source
  Notch/
    NotchViewModel        state, polling, artwork loading
    NotchView             SwiftUI UI: notch shape, card, controls
    NotchWindow           NSPanel above the menu bar, non-activating
    NotchController        screen geometry, mouse tracking, pass-through
    PassthroughHostingView  lets clicks pass through outside the notch
scripts/
  build_app.sh            builds and packages the .app
```

---

## Launch at login (optional)

For now it starts manually. To launch it automatically, add `build/iNotch.app`
under **System Settings → General → Login Items**. (An app-managed login item
is on the roadmap.)

---

## Roadmap

- [x] Progress bar + seek + volume control
- [ ] Like / favorite and shuffle / repeat toggles
- [ ] Artwork-based theming
- [ ] Full-width artwork and "liquid" animations
- [ ] Control Center–style panels (brightness, volume, toggles, shortcuts)
- [ ] File dock / drag-and-drop into the notch
- [ ] Preferences (launch at login, screen choice, sizing)
- [ ] Notarization for distribution outside this Mac
```

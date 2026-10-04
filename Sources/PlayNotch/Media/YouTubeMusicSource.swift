import Foundation

/// YouTube Music has no scripting dictionary of its own, so we drive it
/// through whatever browser has a `music.youtube.com` tab open. We read the
/// now-playing state by injecting JavaScript and send transport commands by
/// clicking the page's own controls.
///
/// REQUIREMENT: the browser must allow JavaScript from Apple Events.
///   • Safari:  Develop ▸ "Allow JavaScript from Apple Events"
///   • Chrome:  View ▸ Developer ▸ "Allow JavaScript from Apple Events"
/// Without this the read/commands silently no-op.
final class YouTubeMusicSource: MediaSource {
    let app: MediaApp = .youtubeMusic

    /// Browsers we know how to script, in priority order. Chromium-family
    /// browsers share the "execute … javascript" syntax; Safari differs.
    private struct Browser {
        let appName: String
        let bundleID: String
        let isSafari: Bool
    }

    private let browsers: [Browser] = [
        Browser(appName: "Google Chrome", bundleID: "com.google.Chrome", isSafari: false),
        Browser(appName: "Brave Browser", bundleID: "com.brave.Browser", isSafari: false),
        Browser(appName: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isSafari: false),
        Browser(appName: "Arc", bundleID: "company.thebrowser.Browser", isSafari: false),
        Browser(appName: "Safari", bundleID: "com.apple.Safari", isSafari: true),
    ]

    func isRunning() -> Bool {
        browsers.contains { AppleScriptRunner.isRunning(bundleID: $0.bundleID) }
    }

    func fetch() -> NowPlaying? {
        for browser in browsers where AppleScriptRunner.isRunning(bundleID: browser.bundleID) {
            guard let raw = AppleScriptRunner.string(script(for: browser, js: Self.readJS)),
                  !raw.isEmpty else { continue }

            let parts = raw.components(separatedBy: "\t")
            guard parts.count >= 11 else { continue }

            let title = parts[1]
            guard !title.isEmpty else { continue }

            let state: PlaybackState = parts[0] == "playing" ? .playing : .paused
            // Remember which browser is hosting playback, so commands hit it.
            lastBrowser = browser

            return NowPlaying(
                app: .youtubeMusic,
                title: title,
                artist: parts[2],
                album: parts[3],
                state: state,
                duration: Double(parts[5]),
                position: Double(parts[6]),
                artworkURL: URL(string: parts[4]),
                artworkData: nil,
                volume: Double(parts[7]),
                isShuffle: parts[8].isEmpty ? nil : (parts[8] == "true"),
                repeatMode: parseRepeatMode(parts[9]),
                isFavorite: parts[10].isEmpty ? nil : (parts[10] == "LIKE")
            )
        }
        return nil
    }

    // MARK: - Transport

    private var lastBrowser: Browser?

    func playPause() { runCommand(Self.playPauseJS) }
    func nextTrack() { runCommand(Self.nextJS) }
    func previousTrack() { runCommand(Self.prevJS) }

    func seek(to seconds: Double) {
        // Build the JS inline: set the <video> element's currentTime.
        let js = "(function(){var v=document.querySelector('video');"
            + "if(v){v.currentTime=\(seconds);}return 'ok';})()"
        runCommand(js)
    }

    func toggleShuffle() { runCommand(Self.shuffleJS) }
    func cycleRepeat() { runCommand(Self.repeatJS) }
    func toggleFavorite() { runCommand(Self.likeJS) }

    func activate() {
        let targets: [Browser]
        if let last = lastBrowser, AppleScriptRunner.isRunning(bundleID: last.bundleID) {
            targets = [last]
        } else {
            targets = browsers.filter { AppleScriptRunner.isRunning(bundleID: $0.bundleID) }
        }
        guard let browser = targets.first else { return }
        AppleScriptRunner.run(activateScript(for: browser))
    }

    /// Activate the browser and focus the first YouTube Music tab.
    private func activateScript(for browser: Browser) -> String {
        if browser.isSafari {
            return """
            tell application "\(browser.appName)"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "music.youtube.com" then
                            set current tab of w to t
                            set miniaturized of w to false
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        } else {
            return """
            tell application "\(browser.appName)"
                activate
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if (URL of t) contains "music.youtube.com" then
                            set active tab index of w to i
                            set minimized of w to false
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }
    }

    /// Repeat comes in two shapes:
    ///  • old bar: a non-localized `repeat-mode` attribute — NONE / ALL / ONE;
    ///  • new player: "NONE", or "P:<label>" when on. ALL and ONE differ only
    ///    by the localized label, so we learn which label is which from the
    ///    button's fixed cycle (off → all → one), with a word heuristic until
    ///    we've seen the cycle.
    private var repeatAllLabel: String?
    private var repeatOneLabel: String?
    private var lastRepeat: (mode: RepeatMode, label: String)?

    private func parseRepeatMode(_ s: String) -> RepeatMode? {
        switch s {
        case "ALL", "ALL_QUEUE": return .all
        case "ONE": return .one
        case "NONE":
            lastRepeat = (.off, "")
            return .off
        default: break
        }
        guard s.hasPrefix("P:") else { return nil }
        let label = String(s.dropFirst(2))

        let mode: RepeatMode
        if label == repeatAllLabel {
            mode = .all
        } else if label == repeatOneLabel {
            mode = .one
        } else if let last = lastRepeat, last.mode == .off {
            repeatAllLabel = label
            mode = .all
        } else if let last = lastRepeat, last.mode == .all, last.label != label {
            repeatOneLabel = label
            mode = .one
        } else {
            mode = Self.labelLooksLikeRepeatOne(label) ? .one : .all
        }
        lastRepeat = (mode, label)
        return mode
    }

    /// "Repeat one" / "Ripeti uno" / "Einen wiederholen" / "Répéter un titre"…
    private static func labelLooksLikeRepeatOne(_ label: String) -> Bool {
        let words = label.lowercased().split { !$0.isLetter && !$0.isNumber }
        let one: Set<Substring> = ["one", "uno", "una", "un", "une", "eins", "einen", "um", "uma", "een", "1"]
        return words.contains { one.contains($0) }
    }

    func setVolume(_ value: Double) {
        let v = min(max(value, 0), 1)
        let pct = Int((v * 100).rounded())
        // Drive YTM's player API so the change sticks (setting <video>.volume
        // gets reverted by YTM's own volume state); fall back to the element.
        let js = "(function(){var mp=document.querySelector('#movie_player');"
            + "if(mp&&typeof mp.setVolume==='function'){mp.setVolume(\(pct));"
            + "if(\(pct)>0&&typeof mp.unMute==='function'){mp.unMute();}return 'ok';}"
            + "var e=document.querySelector('video');if(e){e.volume=\(v);e.muted=false;}return 'ok';})()"
        runCommand(js)
    }

    private func runCommand(_ js: String) {
        // Prefer the browser we last read from; otherwise probe all of them.
        let targets: [Browser]
        if let last = lastBrowser, AppleScriptRunner.isRunning(bundleID: last.bundleID) {
            targets = [last]
        } else {
            targets = browsers.filter { AppleScriptRunner.isRunning(bundleID: $0.bundleID) }
        }
        for browser in targets {
            AppleScriptRunner.run(script(for: browser, js: js))
        }
    }

    // MARK: - AppleScript assembly

    /// Build an AppleScript that finds the first YT Music tab in `browser`
    /// and evaluates `js` inside it, returning the JS result.
    private func script(for browser: Browser, js: String) -> String {
        if browser.isSafari {
            return """
            tell application "\(browser.appName)"
                if it is not running then return ""
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "music.youtube.com" then
                            return (do JavaScript "\(js)" in t)
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        } else {
            return """
            tell application "\(browser.appName)"
                if it is not running then return ""
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "music.youtube.com" then
                            return (execute t javascript "\(js)")
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        }
    }

    // MARK: - Injected JavaScript
    //
    // IMPORTANT: these strings are embedded inside an AppleScript double-quoted
    // literal, so they must contain NO double quotes and NO backslashes. We use
    // single quotes throughout and String.fromCharCode(9) for the tab field
    // separator. Keep each one a single line.

    // YTM shipped a redesigned player (2026-10): `<ytmusic-player-bar>` is
    // gone, replaced by `<ytmusic-miniplayer>` with `ytmusic-track-info` and
    // `ytmusic-wiz-player-controls`. Its buttons sit in wrappers with stable,
    // language-independent classes (`.ytmusicPlayerControlsNextButton`, …).
    // Every lookup tries the new layout first and falls back to the old one,
    // since YTM rolls redesigns out gradually.
    //
    // Title/artist/album/artwork come from `navigator.mediaSession.metadata`
    // first: it's a standard browser API, so it survives DOM redesigns.

    private static let readJS =
        "(function(){var v=document.querySelector('video');" +
        "var title='',artist='',album='',art='';" +
        "var md=navigator.mediaSession&&navigator.mediaSession.metadata;" +
        "if(md&&md.title){title=md.title;artist=md.artist||'';album=md.album||'';" +
        "if(md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src||'';}}" +
        "if(!title){var by='';var ti=document.querySelector('ytmusic-track-info');" +
        "if(ti){var te=ti.querySelector('.ytmusicTrackInfoTitle');title=te?(te.getAttribute('title')||te.textContent||''):'';" +
        "var be=ti.querySelector('.ytmusicTrackInfoBylineItem');by=be?(be.getAttribute('title')||be.textContent||''):'';" +
        "var ie=ti.querySelector('img.ytmusicTrackInfoThumbnail');if(ie){art=ie.src;}}" +
        "else{var t=document.querySelector('.title.ytmusic-player-bar');title=t?(t.textContent||''):'';" +
        "var b=document.querySelector('.byline.ytmusic-player-bar');by=b?(b.getAttribute('title')||b.textContent||''):'';" +
        "var im=document.querySelector('#song-image img')||document.querySelector('img.ytmusic-player-bar');if(im){art=im.src;}}" +
        "var parts=by.split('•').map(function(s){return s.trim();});" +
        "artist=parts[0]||'';album=(parts.length>1?parts[1]:'')||'';}" +
        "title=title.trim();if(!title){return '';}" +
        "var st=(v&&!v.paused)?'playing':'paused';" +
        "var dur=(v&&isFinite(v.duration)&&v.duration>0)?v.duration:0;" +
        "var pos=(v&&isFinite(v.currentTime))?v.currentTime:0;" +
        "if(!dur){var s=document.querySelector('input.ytMusicMiniPlayerProgressBar')||document.querySelector('#progress-bar');if(s){var mx=parseFloat(s.getAttribute('max')||s.getAttribute('aria-valuemax'));if(isFinite(mx)&&mx>0){dur=mx;var nw=parseFloat(s.value||s.getAttribute('aria-valuenow'));if(isFinite(nw)){pos=nw;}}}}" +
        // Read the volume from YTM's own player API (getVolume is 0-100), not
        // the raw <video>.volume which YTM keeps overwriting from its own state.
        "var mp=document.querySelector('#movie_player');var vol=1;" +
        "if(mp&&typeof mp.getVolume==='function'){vol=(mp.isMuted&&mp.isMuted())?0:(mp.getVolume()/100);}" +
        "else if(v&&isFinite(v.volume)){vol=v.volume;}" +
        // Repeat: the new button only exposes aria-pressed (on/off) plus a
        // localized label that tells ALL from ONE, so send 'P:<label>' and let
        // Swift resolve it. The old bar has a `repeat-mode` attribute.
        "var rm='';var rb=document.querySelector('.ytmusicPlayerControlsRepeatButton button');" +
        "if(rb){rm=(rb.getAttribute('aria-pressed')==='true')?('P:'+(rb.getAttribute('aria-label')||'')):'NONE';}" +
        "else{var bar=document.querySelector('ytmusic-player-bar');rm=bar?(bar.getAttribute('repeat-mode')||''):'';}" +
        // Shuffle: new button has aria-pressed. The old one has no state
        // attribute, but is colored white when active and grey when not.
        "var shuf='';var nsb=document.querySelector('.ytmusicPlayerControlsShuffleButton button');" +
        "if(nsb){shuf=(nsb.getAttribute('aria-pressed')==='true')?'true':'false';}" +
        "else{var sb=document.querySelector('ytmusic-player-bar .shuffle');" +
        "if(sb){var sc=getComputedStyle(sb).color;var sr=parseInt((sc.split('(')[1]||'0').split(',')[0]);if(isFinite(sr)){shuf=(sr>190)?'true':'false';}}}" +
        "var like='';var lb=document.querySelector('ytmusic-miniplayer like-button-view-model button');" +
        "if(lb){like=(lb.getAttribute('aria-pressed')==='true')?'LIKE':'INDIFFERENT';}" +
        "else{var lr=document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer');like=lr?(lr.getAttribute('like-status')||''):'';}" +
        "var TAB=String.fromCharCode(9);" +
        "return st+TAB+title+TAB+artist+TAB+album+TAB+art+TAB+dur+TAB+pos+TAB+vol+TAB+shuf+TAB+rm+TAB+like;})()"

    /// Click the first element matching any of `selectors` (new layout first,
    /// old as fallback); if none exists, run `fallback` JS instead.
    private static func clickJS(_ selectors: [String], fallback: String = "") -> String {
        let list = selectors.map { "'\($0)'" }.joined(separator: ",")
        return "(function(){var s=[\(list)];for(var i=0;i<s.length;i++){"
            + "var e=document.querySelector(s[i]);if(e){e.click();return 'ok';}}"
            + "\(fallback)return 'ok';})()"
    }

    // On the old bar we click the `yt-icon-button` wrapper itself (clicking the
    // inner <button> doesn't fire YTM's Polymer tap handler); on the new one
    // the inner <button> is the real control.
    private static let playPauseJS = clickJS(
        [".ytmusicPlayerControlsPlayPauseButton button", "#play-pause-button"],
        fallback: "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}")

    private static let nextJS = clickJS(
        [".ytmusicPlayerControlsNextButton button", ".next-button"],
        fallback: "var mp=document.querySelector('#movie_player');if(mp&&mp.nextVideo){mp.nextVideo();}")

    private static let prevJS = clickJS(
        [".ytmusicPlayerControlsPreviousButton button", ".previous-button"],
        fallback: "var mp=document.querySelector('#movie_player');if(mp&&mp.previousVideo){mp.previousVideo();}")

    private static let shuffleJS = clickJS(
        [".ytmusicPlayerControlsShuffleButton button", "ytmusic-player-bar .shuffle"])

    private static let repeatJS = clickJS(
        [".ytmusicPlayerControlsRepeatButton button", "ytmusic-player-bar .repeat"])

    // Target the thumbs-up by its own element/id — the DOM order of
    // like/dislike is NOT stable (it flipped once, and clicking dislike skips
    // the track).
    private static let likeJS = clickJS(
        ["ytmusic-miniplayer like-button-view-model button",
         "ytmusic-player-bar ytmusic-like-button-renderer #button-shape-like button"])
}

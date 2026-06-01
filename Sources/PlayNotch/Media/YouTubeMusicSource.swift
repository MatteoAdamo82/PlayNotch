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
                repeatMode: Self.parseRepeatMode(parts[9]),
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

    /// YTM exposes repeat as a non-localized `repeat-mode` attribute on
    /// `<ytmusic-player-bar>`: NONE / ALL / ONE.
    private static func parseRepeatMode(_ s: String) -> RepeatMode? {
        switch s {
        case "ALL", "ALL_QUEUE": return .all
        case "ONE": return .one
        case "NONE": return .off
        default: return nil
        }
    }

    func setVolume(_ value: Double) {
        let v = min(max(value, 0), 1)
        let js = "(function(){var e=document.querySelector('video');"
            + "if(e){e.volume=\(v);e.muted=false;}return 'ok';})()"
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

    private static let readJS =
        "(function(){var v=document.querySelector('video');" +
        "var t=document.querySelector('.title.ytmusic-player-bar');" +
        "if(!t||!t.textContent){return '';}" +
        "var title=t.textContent.trim();" +
        "var b=document.querySelector('.byline.ytmusic-player-bar');" +
        "var by=(b?(b.getAttribute('title')||b.textContent):'')||'';" +
        "var parts=by.split('•').map(function(s){return s.trim();});" +
        "var artist=parts[0]||'';" +
        "var album=(parts.length>2?parts[1]:'')||'';" +
        "var art='';try{var im=document.querySelector('#song-image img')||document.querySelector('img.ytmusic-player-bar');if(im){art=im.src;}}catch(e){}" +
        "var st=(v&&!v.paused)?'playing':'paused';" +
        "var dur=(v&&isFinite(v.duration)&&v.duration>0)?v.duration:0;" +
        "var pos=(v&&isFinite(v.currentTime))?v.currentTime:0;" +
        "if(!dur){var s=document.querySelector('#progress-bar');if(s){var mx=parseFloat(s.getAttribute('aria-valuemax'));if(isFinite(mx)&&mx>0){dur=mx;var nw=parseFloat(s.getAttribute('aria-valuenow'));if(isFinite(nw)){pos=nw;}}}}" +
        "var vol=(v&&isFinite(v.volume))?v.volume:1;" +
        "var bar=document.querySelector('ytmusic-player-bar');" +
        "var rm=bar?(bar.getAttribute('repeat-mode')||''):'';" +
        // Shuffle has no state attribute, but the button is colored white when
        // active and grey when not — read its computed color's red channel.
        "var sb=document.querySelector('ytmusic-player-bar .shuffle');" +
        "var shuf='';if(sb){var sc=getComputedStyle(sb).color;var sr=parseInt((sc.split('(')[1]||'0').split(',')[0]);if(isFinite(sr)){shuf=(sr>190)?'true':'false';}}" +
        "var lr=document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer');" +
        "var like=lr?(lr.getAttribute('like-status')||''):'';" +
        "var TAB=String.fromCharCode(9);" +
        "return st+TAB+title+TAB+artist+TAB+album+TAB+art+TAB+dur+TAB+pos+TAB+vol+TAB+shuf+TAB+rm+TAB+like;})()"

    private static let playPauseJS =
        "(function(){var p=document.querySelector('#play-pause-button');" +
        "if(p){p.click();return 'ok';}" +
        "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}return 'ok';})()"

    private static let nextJS =
        "(function(){var n=document.querySelector('.next-button');if(n){n.click();}return 'ok';})()"

    private static let prevJS =
        "(function(){var p=document.querySelector('.previous-button');if(p){p.click();}return 'ok';})()"

    // The player-bar wrapper buttons carry stable, language-independent class
    // names (`.shuffle` / `.repeat`) even when the UI is localized. We click the
    // `yt-icon-button` wrapper itself (clicking the inner <button> doesn't fire
    // YTM's Polymer tap handler) — the same way the transport buttons work.
    private static let shuffleJS =
        "(function(){var e=document.querySelector('ytmusic-player-bar .shuffle');"
        + "if(e){e.click();}return 'ok';})()"

    private static let repeatJS =
        "(function(){var e=document.querySelector('ytmusic-player-bar .repeat');"
        + "if(e){e.click();}return 'ok';})()"

    // Click the like (thumbs-up) button — the last button in the like renderer
    // (the first is dislike), language-independent.
    private static let likeJS =
        "(function(){var lr=document.querySelector('ytmusic-player-bar ytmusic-like-button-renderer');"
        + "if(lr){var b=lr.querySelectorAll('button');if(b.length){b[b.length-1].click();}}return 'ok';})()"
}

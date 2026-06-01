import Foundation

/// Spotify via AppleScript. Provides an artwork URL (not raw data).
final class SpotifySource: MediaSource {
    let app: MediaApp = .spotify
    private let bundleID = "com.spotify.client"

    func isRunning() -> Bool {
        AppleScriptRunner.isRunning(bundleID: bundleID)
    }

    func fetch() -> NowPlaying? {
        guard isRunning() else { return nil }

        let script = """
        tell application "Spotify"
            if it is not running then return ""
            try
                set st to player state as string
            on error
                return ""
            end try
            set theVol to (sound volume as string)
            try
                set theShuf to (shuffling as string)
            on error
                set theShuf to "false"
            end try
            try
                set theRep to (repeating as string)
            on error
                set theRep to "false"
            end try
            try
                set t to current track
                set theTitle to name of t
                set theArtist to artist of t
                set theAlbum to album of t
                set theArt to artwork url of t
                set theDur to (((duration of t) / 1000) as string)
                set pos to ((player position) as string)
            on error
                return st & tab & "" & tab & "" & tab & "" & tab & "" & tab & "0" & tab & "0" & tab & theVol & tab & theShuf & tab & theRep
            end try
            return st & tab & theTitle & tab & theArtist & tab & theAlbum & tab & theArt & tab & theDur & tab & pos & tab & theVol & tab & theShuf & tab & theRep
        end tell
        """

        guard let raw = AppleScriptRunner.string(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 10 else { return nil }

        let state: PlaybackState
        switch parts[0] {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }

        let title = parts[1]
        guard !title.isEmpty else { return nil }

        return NowPlaying(
            app: .spotify,
            title: title,
            artist: parts[2],
            album: parts[3],
            state: state,
            duration: Double(parts[5]),
            position: Double(parts[6]),
            artworkURL: URL(string: parts[4]),
            artworkData: nil,
            volume: Double(parts[7]).map { $0 / 100 },
            isShuffle: parts[8] == "true",
            repeatMode: parts[9] == "true" ? .all : .off
        )
    }

    func playPause() { AppleScriptRunner.run(#"tell application "Spotify" to playpause"#) }
    func nextTrack() { AppleScriptRunner.run(#"tell application "Spotify" to next track"#) }
    func previousTrack() { AppleScriptRunner.run(#"tell application "Spotify" to previous track"#) }

    func seek(to seconds: Double) {
        AppleScriptRunner.run(#"tell application "Spotify" to set player position to \#(seconds)"#)
    }

    func setVolume(_ value: Double) {
        let v = Int((min(max(value, 0), 1) * 100).rounded())
        AppleScriptRunner.run(#"tell application "Spotify" to set sound volume to \#(v)"#)
    }

    func toggleShuffle() {
        AppleScriptRunner.run(#"tell application "Spotify" to set shuffling to not shuffling"#)
    }

    // Spotify's AppleScript exposes repeat only as a boolean, so we toggle
    // between off and repeat-all (no separate repeat-one).
    func cycleRepeat() {
        AppleScriptRunner.run(#"tell application "Spotify" to set repeating to not repeating"#)
    }
}

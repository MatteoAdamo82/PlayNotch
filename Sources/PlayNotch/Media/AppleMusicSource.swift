import Foundation

/// Apple Music (Music.app) via AppleScript. Has a rich scripting dictionary,
/// including raw artwork data.
final class AppleMusicSource: MediaSource {
    let app: MediaApp = .appleMusic
    private let bundleID = "com.apple.Music"

    func isRunning() -> Bool {
        AppleScriptRunner.isRunning(bundleID: bundleID)
    }

    func fetch() -> NowPlaying? {
        guard isRunning() else { return nil }

        // Pull the core fields in one round-trip, tab-separated.
        let script = """
        tell application "Music"
            if it is not running then return ""
            try
                set st to player state as string
            on error
                return ""
            end try
            set theVol to (sound volume as string)
            try
                set theShuf to (shuffle enabled as string)
            on error
                set theShuf to "false"
            end try
            try
                set theRep to (song repeat as string)
            on error
                set theRep to "off"
            end try
            if player position is missing value then
                set pos to "0"
            else
                set pos to (player position as string)
            end if
            try
                set t to current track
                set theTitle to name of t
                set theArtist to artist of t
                set theAlbum to album of t
                set theDur to ((duration of t) as string)
            on error
                return st & tab & "" & tab & "" & tab & "" & tab & "0" & tab & pos & tab & theVol & tab & theShuf & tab & theRep
            end try
            return st & tab & theTitle & tab & theArtist & tab & theAlbum & tab & theDur & tab & pos & tab & theVol & tab & theShuf & tab & theRep
        end tell
        """

        guard let raw = AppleScriptRunner.string(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 9 else { return nil }

        let state: PlaybackState
        switch parts[0] {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }

        let title = parts[1]
        guard !title.isEmpty else { return nil }

        return NowPlaying(
            app: .appleMusic,
            title: title,
            artist: parts[2],
            album: parts[3],
            state: state,
            duration: Double(parts[4]),
            position: Double(parts[5]),
            artworkURL: nil,
            artworkData: fetchArtwork(),
            volume: Double(parts[6]).map { $0 / 100 },
            isShuffle: parts[7] == "true",
            repeatMode: Self.parseRepeat(parts[8])
        )
    }

    private static func parseRepeat(_ s: String) -> RepeatMode {
        switch s {
        case "all": return .all
        case "one": return .one
        default: return .off
        }
    }

    /// Artwork comes back as raw image data from the scripting bridge.
    private func fetchArtwork() -> Data? {
        let script = """
        tell application "Music"
            try
                if (count of artworks of current track) is 0 then return missing value
                return data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """
        guard let descriptor = AppleScriptRunner.run(script) else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    func playPause() { AppleScriptRunner.run(#"tell application "Music" to playpause"#) }
    func nextTrack() { AppleScriptRunner.run(#"tell application "Music" to next track"#) }
    func previousTrack() { AppleScriptRunner.run(#"tell application "Music" to previous track"#) }

    func seek(to seconds: Double) {
        AppleScriptRunner.run(#"tell application "Music" to set player position to \#(seconds)"#)
    }

    func setVolume(_ value: Double) {
        let v = Int((min(max(value, 0), 1) * 100).rounded())
        AppleScriptRunner.run(#"tell application "Music" to set sound volume to \#(v)"#)
    }

    func toggleShuffle() {
        AppleScriptRunner.run(#"tell application "Music" to set shuffle enabled to not (shuffle enabled)"#)
    }

    func cycleRepeat() {
        AppleScriptRunner.run("""
        tell application "Music"
            set r to song repeat
            if r is off then
                set song repeat to all
            else if r is all then
                set song repeat to one
            else
                set song repeat to off
            end if
        end tell
        """)
    }
}

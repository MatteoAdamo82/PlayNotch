import AppKit

/// Which app a now-playing snapshot came from.
enum MediaApp: String, CaseIterable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"

    var symbolName: String {
        switch self {
        case .appleMusic: return "music.note"
        case .spotify: return "music.note.list"
        case .youtubeMusic: return "play.rectangle.fill"
        }
    }
}

enum PlaybackState {
    case playing
    case paused
    case stopped
}

enum RepeatMode {
    case off
    case all
    case one
}

/// Immutable snapshot of what is currently playing.
struct NowPlaying: Equatable {
    var app: MediaApp
    var title: String
    var artist: String
    var album: String
    var state: PlaybackState
    /// Track duration in seconds, if known.
    var duration: Double?
    /// Current playback position in seconds, if known.
    var position: Double?
    /// Remote artwork URL (Spotify provides this directly).
    var artworkURL: URL?
    /// Inline artwork bytes (Apple Music provides raw data).
    var artworkData: Data?
    /// Output volume in 0...1, if known.
    var volume: Double?
    /// Whether shuffle is on, if known.
    var isShuffle: Bool?
    /// Repeat mode, if known.
    var repeatMode: RepeatMode?
    /// Whether the track is favorited/liked (nil = source doesn't support it).
    var isFavorite: Bool?

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.app == rhs.app &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.state == rhs.state &&
        lhs.artworkURL == rhs.artworkURL &&
        lhs.artworkData == rhs.artworkData
    }
}

/// A controllable media source (one per supported app).
protocol MediaSource: AnyObject {
    var app: MediaApp { get }

    /// Whether the backing app is currently running. Cheap to call.
    func isRunning() -> Bool

    /// Fetch the current now-playing snapshot, or nil if nothing is playing
    /// or the app is not running.
    func fetch() -> NowPlaying?

    func playPause()
    func nextTrack()
    func previousTrack()

    /// Seek the current track to an absolute position in seconds.
    func seek(to seconds: Double)

    /// Set the output volume, where `value` is in 0...1.
    func setVolume(_ value: Double)

    /// Toggle shuffle on/off.
    func toggleShuffle()

    /// Advance the repeat mode (off → all → one → off).
    func cycleRepeat()

    /// Toggle the favorite/like state of the current track.
    func toggleFavorite()

    /// Bring the source app (or its tab) to the front.
    func activate()
}

extension MediaSource {
    /// Default: sources that can't favorite do nothing.
    func toggleFavorite() {}
}

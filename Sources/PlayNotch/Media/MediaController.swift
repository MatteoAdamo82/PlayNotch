import Foundation

/// Aggregates all media sources and decides which one is "active".
///
/// Selection rule:
///   1. Prefer a source that is currently `playing`.
///   2. Otherwise keep the previously active source if it is still running
///      and has a track (so pausing doesn't make the widget jump around).
///   3. Otherwise fall back to the first running source with a track.
final class MediaController {
    private let sources: [MediaSource]
    private var activeApp: MediaApp?

    init() {
        // Order matters as a tie-breaker.
        self.sources = [
            AppleMusicSource(),
            SpotifySource(),
            YouTubeMusicSource(),
        ]
    }

    /// Poll every source and return the chosen now-playing snapshot.
    func current() -> NowPlaying? {
        var snapshots: [NowPlaying] = []
        for source in sources where source.isRunning() {
            if let snap = source.fetch() {
                snapshots.append(snap)
            }
        }

        guard !snapshots.isEmpty else {
            activeApp = nil
            return nil
        }

        // 1. Anything actively playing wins.
        if let playing = snapshots.first(where: { $0.state == .playing }) {
            activeApp = playing.app
            return playing
        }

        // 2. Stick with the previously active source if still present.
        if let active = activeApp,
           let kept = snapshots.first(where: { $0.app == active }) {
            return kept
        }

        // 3. Fall back to the first available.
        let first = snapshots[0]
        activeApp = first.app
        return first
    }

    private func source(for app: MediaApp) -> MediaSource? {
        sources.first { $0.app == app }
    }

    func playPause() { activeSource()?.playPause() }
    func nextTrack() { activeSource()?.nextTrack() }
    func previousTrack() { activeSource()?.previousTrack() }
    func seek(to seconds: Double) { activeSource()?.seek(to: seconds) }
    func setVolume(_ value: Double) { activeSource()?.setVolume(value) }
    func toggleShuffle() { activeSource()?.toggleShuffle() }
    func cycleRepeat() { activeSource()?.cycleRepeat() }

    private func activeSource() -> MediaSource? {
        if let activeApp, let s = source(for: activeApp) { return s }
        return sources.first { $0.isRunning() }
    }
}

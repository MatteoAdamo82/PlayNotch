import Foundation

/// Aggregates all media sources and decides which one is "active".
///
/// Selection rule, in order:
///   1. A source that *just started* playing (was not playing last poll) grabs
///      control — so the last thing you hit play on wins, even if another app
///      is also playing.
///   2. Keep the active source while it keeps playing.
///   3. Any other source that is currently playing (e.g. after you pause the
///      active one, hand off to whatever is still playing).
///   4. Keep the previously active source if it's still present but paused, so
///      the widget doesn't jump around.
///   5. Fall back to the first available source.
final class MediaController {
    private let sources: [MediaSource]
    private var activeApp: MediaApp?
    /// Last seen playback state per app, to detect "just started playing".
    private var lastStates: [MediaApp: PlaybackState] = [:]

    init() {
        // Order matters only as a final tie-breaker.
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
            lastStates = [:]
            return nil
        }

        let playing = snapshots.filter { $0.state == .playing }
        // Sources that transitioned into playing since the last poll.
        let justStarted = playing.filter { lastStates[$0.app] != .playing }

        // Record current states for the next poll's transition detection.
        var states: [MediaApp: PlaybackState] = [:]
        for snap in snapshots { states[snap.app] = snap.state }
        lastStates = states

        // 1. The source you most recently started playing wins.
        if let started = justStarted.first {
            activeApp = started.app
            return started
        }
        // 2. Keep the active source while it's still playing.
        if let active = activeApp, let kept = playing.first(where: { $0.app == active }) {
            return kept
        }
        // 3. Otherwise hand off to any source that is playing.
        if let anyPlaying = playing.first {
            activeApp = anyPlaying.app
            return anyPlaying
        }
        // 4. Nothing playing: keep the previously active source if still present.
        if let active = activeApp, let kept = snapshots.first(where: { $0.app == active }) {
            return kept
        }
        // 5. Fall back to the first available.
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

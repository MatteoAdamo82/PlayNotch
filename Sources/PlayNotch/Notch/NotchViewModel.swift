import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchViewModel: ObservableObject {
    /// Whether the notch card is expanded (hover state).
    @Published var isExpanded = false

    /// Current track, or nil when nothing is playing / no app running.
    @Published private(set) var nowPlaying: NowPlaying?

    /// Resolved artwork image for the current track.
    @Published private(set) var artwork: NSImage? {
        didSet { accentColor = artwork?.vibrantColor().map { Color(nsColor: $0) } ?? .white }
    }

    /// A vibrant accent colour derived from the current artwork (white when
    /// there's no artwork), used to theme the card, bars and toggles.
    @Published private(set) var accentColor: Color = .white

    /// Output volume in 0...1 of the active source.
    @Published var volume: Double = 1
    /// True briefly after a volume change, to highlight the volume control.
    @Published private(set) var isAdjustingVolume = false

    /// Shuffle on/off (nil = unknown for this source).
    @Published private(set) var isShuffle: Bool?
    /// Repeat mode (nil = unknown for this source).
    @Published private(set) var repeatMode: RepeatMode?

    /// Geometry, supplied by the controller from screen metrics.
    @Published var collapsedSize: CGSize = CGSize(width: 200, height: 32)
    @Published var expandedSize: CGSize = CGSize(width: 380, height: 160)

    private let media = MediaController()
    private var timer: Timer?

    // Playback position is polled only once per second; to animate a smooth
    // progress bar we interpolate locally between polls. We remember the last
    // known position and when we learned it, then extrapolate while playing.
    private var anchorPosition: Double = 0
    private var anchorDate = Date()
    private var anchorPlaying = false
    /// Consecutive empty polls; used to ride out the brief gap between tracks.
    private var missCount = 0
    /// Duration of the current track in seconds, if known.
    private(set) var duration: Double?

    /// The current playback position in seconds, interpolated from the last
    /// poll so the progress bar advances smoothly without extra AppleScript.
    func currentPosition() -> Double {
        var pos = anchorPosition
        if anchorPlaying {
            pos += Date().timeIntervalSince(anchorDate)
        }
        if let duration { return min(max(pos, 0), duration) }
        return max(pos, 0)
    }

    // Tiny artwork cache keyed by a stable identity for the current art.
    private var artworkKey: String?

    func start() {
        refresh()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let snapshot = media.current()

        if let snapshot {
            missCount = 0
            if snapshot != nowPlaying {
                nowPlaying = snapshot
                loadArtwork(for: snapshot)
            }
            // Position/duration are intentionally excluded from NowPlaying
            // equality (they change every second), so refresh the interpolation
            // anchor here on every poll regardless of track identity.
            duration = snapshot.duration
            anchorPosition = snapshot.position ?? 0
            anchorDate = Date()
            anchorPlaying = snapshot.state == .playing
            // Keep the slider in sync with the app, but don't fight the user
            // while they're actively turning the knob.
            if !isAdjustingVolume, let v = snapshot.volume {
                volume = min(max(v, 0), 1)
            }
            isShuffle = snapshot.isShuffle
            repeatMode = snapshot.repeatMode
        } else {
            // Scriptable apps briefly report nothing *between* tracks. Don't blank
            // the UI on a single empty poll — keep the last known state for one
            // grace cycle so the card and progress bar don't flicker on skip.
            missCount += 1
            guard missCount >= 2 else { return }
            if nowPlaying != nil {
                nowPlaying = nil
                loadArtwork(for: nil)
            }
            duration = nil
            anchorPlaying = false
        }
    }

    // MARK: - Seek

    /// Seek to a fraction (0...1) of the current track and optimistically move
    /// the local anchor so the bar reacts instantly, before the next poll.
    func seek(toFraction fraction: Double) {
        guard let duration, duration > 0 else { return }
        let target = min(max(fraction, 0), 1) * duration
        media.seek(to: target)
        anchorPosition = target
        anchorDate = Date()
        bumpRefresh()
    }

    // MARK: - Volume

    private var volumeFlashWork: DispatchWorkItem?

    /// Nudge the volume by a relative delta (e.g. from a scroll wheel).
    func adjustVolume(by delta: Double) {
        setVolume(toFraction: volume + delta)
    }

    /// Set the volume to an absolute fraction (0...1) and push it to the app.
    func setVolume(toFraction fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        guard abs(clamped - volume) > 0.0001 else { return }
        volume = clamped
        media.setVolume(clamped)
        flashVolume()
    }

    /// Mark the volume control as "being adjusted" for a short window so the
    /// poll doesn't immediately overwrite the user's value and the UI can
    /// highlight it.
    private func flashVolume() {
        isAdjustingVolume = true
        volumeFlashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isAdjustingVolume = false }
        volumeFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - Transport

    func playPause() { media.playPause(); bumpRefresh() }
    func nextTrack() { media.nextTrack(); bumpRefresh() }
    func previousTrack() { media.previousTrack(); bumpRefresh() }

    func toggleShuffle() {
        // Optimistic flip so the icon reacts instantly; the poll re-syncs.
        if let s = isShuffle { isShuffle = !s }
        media.toggleShuffle()
        bumpRefresh()
    }

    func cycleRepeat() {
        if let r = repeatMode {
            switch r {
            case .off: repeatMode = .all
            case .all: repeatMode = .one
            case .one: repeatMode = .off
            }
        }
        media.cycleRepeat()
        bumpRefresh()
    }

    /// Give the target app a beat to update, then re-read state.
    private func bumpRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Artwork

    private func loadArtwork(for snapshot: NowPlaying?) {
        guard let snapshot else {
            artwork = nil
            artworkKey = nil
            return
        }

        if let data = snapshot.artworkData {
            let key = "data:\(snapshot.title)|\(snapshot.album)"
            guard key != artworkKey else { return }
            artworkKey = key
            artwork = NSImage(data: data)
            return
        }

        if let url = snapshot.artworkURL {
            let key = "url:\(url.absoluteString)"
            guard key != artworkKey else { return }
            artworkKey = key
            artwork = nil
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                Task { @MainActor in
                    // Only apply if the track hasn't changed since the request.
                    guard let self, self.artworkKey == key else { return }
                    self.artwork = image
                }
            }.resume()
            return
        }

        artwork = nil
        artworkKey = nil
    }
}

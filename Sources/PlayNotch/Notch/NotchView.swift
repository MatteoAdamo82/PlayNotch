import SwiftUI

/// The SwiftUI content that fills the (fixed-size) notch window.
///
/// The window never resizes. Instead we draw a black notch surface whose
/// *frame* animates between a collapsed strip and an expanded card, pinned to
/// the top-center of the canvas. Because the surrounding layout is constant,
/// nothing reflows or jitters during the animation, and `clipShape` guarantees
/// the content can never spill past the notch silhouette.
struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel

    private var expanded: Bool { viewModel.isExpanded }
    private var radius: CGFloat { expanded ? 22 : 10 }

    private var notchWidth: CGFloat {
        expanded ? viewModel.expandedSize.width : viewModel.collapsedSize.width
    }
    private var notchHeight: CGFloat {
        expanded ? viewModel.expandedSize.height : viewModel.collapsedSize.height
    }

    var body: some View {
        let shape = NotchShape(bottomRadius: radius)

        // Top-centered within the fixed canvas. The VStack centers the sized
        // surface horizontally; the Spacer keeps it pinned to the top.
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)

                // Cross-fade collapsed <-> expanded content. Both are laid out
                // inside the animating frame and clipped to the shape.
                ZStack(alignment: .top) {
                    collapsedContent.opacity(expanded ? 0 : 1)
                    expandedContent.opacity(expanded ? 1 : 0)
                }
            }
            .frame(width: notchWidth, height: notchHeight)
            .clipShape(shape)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.nowPlaying)
    }

    // MARK: - Collapsed

    /// The collapsed strip is just the bare black notch.
    private var collapsedContent: some View {
        Color.clear.frame(height: viewModel.collapsedSize.height)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Leave room for the physical notch strip at the very top.
            Spacer().frame(height: viewModel.collapsedSize.height)

            if let np = viewModel.nowPlaying {
                HStack(alignment: .top, spacing: 14) {
                    artworkView
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(np.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(np.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)

                    Spacer()

                    // Source app icon, pinned to the top-right of the card.
                    Image(systemName: np.app.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                if let dur = viewModel.duration, dur > 0 {
                    ProgressBar(viewModel: viewModel)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                }

                // Transport stays centered; shuffle/repeat sit on the left and
                // the compact volume control on the right, so the transport
                // never shifts regardless of the side controls.
                ZStack {
                    TransportControls(viewModel: viewModel, state: np.state)
                    HStack {
                        ExtraControls(viewModel: viewModel)
                        Spacer()
                        VolumeBar(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            } else {
                Spacer()
                Text("Niente in riproduzione")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let image = viewModel.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.1))
                .overlay {
                    Image(systemName: viewModel.nowPlaying?.app.symbolName ?? "music.note")
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }
}

// MARK: - Progress bar

/// A scrubbable playback progress bar. It refreshes on its own lightweight
/// timeline (not the 1s media poll) so the fill advances smoothly, and only
/// writes the seek to the player when the drag ends.
private struct ProgressBar: View {
    @ObservedObject var viewModel: NotchViewModel
    /// Non-nil while the user is dragging: the fraction under the finger.
    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let duration = viewModel.duration ?? 0
            let livePosition = viewModel.currentPosition()
            let fraction = scrubFraction ?? (duration > 0 ? livePosition / duration : 0)
            let shownPosition = scrubFraction.map { $0 * duration } ?? livePosition

            VStack(spacing: 4) {
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: max(0, min(1, fraction)) * width)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                scrubFraction = min(max(v.location.x / width, 0), 1)
                            }
                            .onEnded { v in
                                let f = min(max(v.location.x / width, 0), 1)
                                viewModel.seek(toFraction: f)
                                scrubFraction = nil
                            }
                    )
                }
                .frame(height: 14)

                HStack {
                    Text(Self.time(shownPosition))
                    Spacer()
                    Text(Self.time(duration))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Volume

/// A speaker icon plus a draggable volume slider. Also reflects volume changes
/// made via scrolling over the notch (the controller drives those).
private struct VolumeBar: View {
    @ObservedObject var viewModel: NotchViewModel

    private var icon: String {
        switch viewModel.volume {
        case ..<0.001: return "speaker.slash.fill"
        case ..<0.34: return "speaker.fill"
        case ..<0.67: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    /// Fixed track width so the transport controls stay visually centered.
    private let trackWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 14, alignment: .leading)

            let fraction = min(max(viewModel.volume, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white.opacity(viewModel.isAdjustingVolume ? 1 : 0.7))
                    .frame(width: fraction * trackWidth)
            }
            .frame(width: trackWidth, height: 4)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        viewModel.setVolume(toFraction: v.location.x / trackWidth)
                    }
            )
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.volume)
    }
}

// MARK: - Transport controls

private struct TransportControls: View {
    @ObservedObject var viewModel: NotchViewModel
    let state: PlaybackState

    var body: some View {
        HStack(spacing: 18) {
            controlButton("backward.fill") { viewModel.previousTrack() }
            controlButton(state == .playing ? "pause.fill" : "play.fill", size: 22) {
                viewModel.playPause()
            }
            controlButton("forward.fill") { viewModel.nextTrack() }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat = 16, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shuffle / repeat

/// Secondary controls on the left of the transport row.
private struct ExtraControls: View {
    @ObservedObject var viewModel: NotchViewModel

    private var repeatSymbol: String {
        viewModel.repeatMode == .one ? "repeat.1" : "repeat"
    }
    private var repeatActive: Bool {
        guard let r = viewModel.repeatMode else { return false }
        return r != .off
    }

    var body: some View {
        HStack(spacing: 14) {
            iconButton("shuffle", active: viewModel.isShuffle == true) {
                viewModel.toggleShuffle()
            }
            iconButton(repeatSymbol, active: repeatActive) {
                viewModel.cycleRepeat()
            }
        }
    }

    private func iconButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.4))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Decorations

/// A rounded-rectangle-ish shape that is flat on top (it hugs the screen
/// edge) and rounded on the bottom corners — the classic notch silhouette.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, min(rect.width, rect.height) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

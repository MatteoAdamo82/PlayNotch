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
    @StateObject private var system = SystemControls()

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
                // Solid, opaque black base — keeps the card fully opaque so text
                // always has contrast regardless of what's behind the window.
                shape.fill(Color.black)
                // Blurred, dimmed artwork filling the expanded card (kept black
                // at the very top so the notch strip stays dark).
                if viewModel.artworkBackgroundEnabled, let art = viewModel.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .scaledToFill()
                        .frame(width: notchWidth, height: notchHeight)
                        .blur(radius: 34)
                        .opacity(expanded ? 0.30 : 0)
                        .clipped()
                        .allowsHitTesting(false)
                    // Black gradient over the top so the notch strip stays dark,
                    // fading out smoothly (no hard edge) into the artwork below.
                    shape.fill(
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.34),
                            .init(color: .clear, location: 0.62),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(false)
                }
                // A soft accent tint (only with theming on; otherwise the card
                // stays fully black like the notch).
                if viewModel.themingEnabled {
                    shape.fill(
                        LinearGradient(
                            colors: [.clear, .clear, viewModel.accentColor.opacity(expanded ? 0.32 : 0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }

                // Cross-fade collapsed <-> expanded content. Both are laid out
                // inside the animating frame and clipped to the shape.
                ZStack(alignment: .top) {
                    collapsedContent.opacity(expanded ? 0 : 1)
                    expandedContent.opacity(expanded ? 1 : 0)
                }
            }
            .frame(width: notchWidth, height: notchHeight)
            .clipShape(shape)
            // Scale the whole expanded card (shape + contents) uniformly, pinned
            // at the top, so the layout doesn't leave gaps or overflow.
            .scaleEffect(expanded ? viewModel.sizeScale : 1, anchor: .top)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.nowPlaying)
        .animation(.easeInOut(duration: 0.5), value: viewModel.accentColor)
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
                        .id(np.title + np.album)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .animation(.easeInOut(duration: 0.35), value: viewModel.artwork)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.activateSource() }
                        .help("Open in \(np.app.rawValue)")

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

                    HStack(spacing: 12) {
                        // Favorite / like — only when the source supports it.
                        if viewModel.isFavorite != nil {
                            Button { viewModel.toggleFavorite() } label: {
                                Image(systemName: viewModel.isFavorite == true ? "heart.fill" : "heart")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(viewModel.isFavorite == true ? viewModel.accentColor : Color.white.opacity(0.5))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeOut(duration: 0.15), value: viewModel.isFavorite)
                        }

                        // Source app icon, pinned to the top-right of the card.
                        Image(systemName: np.app.symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)

                // Always mounted (even mid-skip when duration is briefly
                // unknown) so the controls below never jump.
                ProgressBar(viewModel: viewModel)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

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
                .padding(.horizontal, 28)
                .padding(.top, 10)

                if viewModel.showControlCenter {
                    Divider()
                        .overlay(Color.white.opacity(0.1))
                        .padding(.horizontal, 28)
                        .padding(.top, 10)

                    ControlCenterRow(system: system, accent: viewModel.accentColor)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                }
            } else {
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 2) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
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
    /// Mouse x over the bar while hovering (nil when the pointer is away).
    @State private var hoverX: CGFloat?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let duration = viewModel.duration ?? 0
            let livePosition = viewModel.currentPosition()
            let liveFraction = duration > 0 ? min(max(livePosition / duration, 0), 1) : 0

            VStack(spacing: 4) {
                GeometryReader { geo in
                    let width = geo.size.width
                    let target: Double? = scrubFraction ?? hoverX.map { min(max($0 / width, 0), 1) }
                    let active = target != nil
                    let knob = target ?? liveFraction
                    let lo = min(liveFraction, knob)
                    let hi = max(liveFraction, knob)

                    // Only the 4pt bar lives in the ZStack — its height never
                    // changes. The taller time bubble is an overlay, which can't
                    // resize the bar, so nothing grows or shifts on hover.
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                        Capsule().fill(viewModel.accentColor)
                            .frame(width: lo * width, height: 4)
                        if active {
                            Capsule().fill(.white.opacity(0.9))
                                .frame(width: (hi - lo) * width, height: 4)
                                .offset(x: lo * width)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .overlay(alignment: .leading) {
                        if let target {
                            Text(Self.time(target * duration))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.85)))
                                .fixedSize()
                                .offset(x: min(max(target * width - 18, 0), max(0, width - 36)), y: -22)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle().inset(by: -8))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoverX = location.x
                        case .ended: hoverX = nil
                        }
                    }
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
                .frame(height: 12)

                HStack {
                    Text(Self.time(livePosition))
                    Spacer()
                    Text("-" + Self.time(duration - livePosition))
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
    /// Mouse x over the slider while hovering (nil when away).
    @State private var hoverX: CGFloat?

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
            let hoverFraction = hoverX.map { min(max($0 / trackWidth, 0), 1) }
            let lo = min(fraction, hoverFraction ?? fraction)
            let hi = max(fraction, hoverFraction ?? fraction)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                Capsule()
                    .fill(viewModel.accentColor.opacity(viewModel.isAdjustingVolume ? 1 : 0.85))
                    .frame(width: lo * trackWidth, height: 4)
                if hoverFraction != nil {
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: (hi - lo) * trackWidth, height: 4)
                        .offset(x: lo * trackWidth)
                }
            }
            .frame(width: trackWidth, height: 4)
            .overlay(alignment: .leading) {
                if let hoverFraction {
                    Text("\(Int((hoverFraction * 100).rounded()))%")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.85)))
                        .fixedSize()
                        .offset(x: min(max(hoverFraction * trackWidth - 14, -14), trackWidth - 14), y: -20)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle().inset(by: -10))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverX = location.x
                case .ended: hoverX = nil
                }
            }
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

// MARK: - Control Center row

/// System toggles under the music controls: dark mode, keep-awake, lock screen.
private struct ControlCenterRow: View {
    @ObservedObject var system: SystemControls
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            tile(appearanceIcon, appearanceLabel, on: system.appearance != .light) {
                system.cycleAppearance()
            }
            tile("cup.and.saucer.fill", "Awake", on: system.isAwake) { system.toggleAwake() }
            tile("powersleep", "Sleep", on: false) { system.sleepDisplay() }
        }
    }

    private var appearanceIcon: String {
        switch system.appearance {
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        case .auto:  return "circle.lefthalf.filled"
        }
    }
    private var appearanceLabel: String {
        switch system.appearance {
        case .light: return "Light"
        case .dark:  return "Dark"
        case .auto:  return "Auto"
        }
    }

    private func tile(_ icon: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(on ? Color.black : Color.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(on ? accent : Color.white.opacity(0.1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.45))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(active ? viewModel.accentColor : Color.white.opacity(0.12))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: active)
    }
}

// MARK: - Decorations

/// The classic notch silhouette: flush with the screen edge at the top, where
/// the two corners flare out with a small concave curve (like the real notch),
/// vertical sides, and convex rounded bottom corners.
struct NotchShape: Shape {
    /// Concave flare where the top meets the screen edge.
    var topRadius: CGFloat = 9
    /// Convex radius of the two bottom corners (animates collapsed ↔ expanded).
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = min(topRadius, rect.width / 2)
        let br = min(bottomRadius, max(0, (rect.width - 2 * tr) / 2), rect.height / 2)

        // Top edge (full width, flush with the screen).
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right concave flare down into the right side.
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        // Right side down to the bottom-right convex corner.
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - tr - br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge to the bottom-left convex corner.
        p.addLine(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + tr + br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left side up, then the top-left concave flare back to the screen edge.
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

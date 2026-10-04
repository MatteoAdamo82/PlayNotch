import SwiftUI

/// The floating desktop card. Reuses `PlayerCard` (the same now-playing UI as
/// the notch) on a rounded, themed background. Always shows the full card —
/// there's no collapsed state here.
struct DesktopWidgetView: View {
    @ObservedObject var viewModel: NotchViewModel

    // A comfortable fixed card size, independent of the notch geometry.
    // Height is FIXED (not content-driven) so the card never changes shape
    // during a skip, when the duration is briefly unknown, or when it flips to
    // the idle clock. It also reserves enough room that content isn't crammed.
    private let cardWidth: CGFloat = 340
    private var cardHeight: CGFloat { viewModel.showControlCenter ? 232 : 178 }

    var body: some View {
        ZStack {
            // Opaque base so text always has contrast.
            RoundedRectangle(cornerRadius: 20).fill(Color.black)

            // Blurred artwork background (same option as the notch).
            if viewModel.artworkBackgroundEnabled, let art = viewModel.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .opacity(0.35)
                    .allowsHitTesting(false)
            }
            // Accent tint from the artwork.
            if viewModel.themingEnabled {
                RoundedRectangle(cornerRadius: 20).fill(
                    LinearGradient(
                        colors: [viewModel.accentColor.opacity(0.28), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
            }

            // The shared card contents. No top inset — there's no notch strip.
            // Centered vertically within the fixed height.
            PlayerCard(viewModel: viewModel, topInset: 0, verticallyCentered: true)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.5), value: viewModel.accentColor)
    }
}

import SwiftUI

/// Layout note: the prototype uses fixed 1920×1080 absolute coordinates. Here we keep
/// the same *composition* (passthrough behind, a centered glass window/card, a right-edge
/// sidebar, bottom page-dots + home-pill) but let SwiftUI lay it out responsively so it
/// runs on the iPad / Vision Pro simulators the project targets.

// MARK: - 01 · Opening

struct OpeningScreen: View {
    let onBegin: () -> Void
    @State private var breathe = false

    var body: some View {
        ZStack {
            OopsPassthrough()

            // Clean centered image — no glass card frame, no sidebar.
            Image("oops_meadow")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 980, maxHeight: 620)
                .clipShape(RoundedRectangle(cornerRadius: OopsGlass.radiusWindow, style: .continuous))

            // VisualEyes monogram — centred over the preview (matches Figma node 285:1442).
            GlintLogo()

            VStack {
                Spacer()
                Text("Tap anywhere to begin")
                    .oopsSub(20)
                    .opacity(breathe ? 0.95 : 0.45)
                    .padding(.bottom, 120)
                PageDots().padding(.bottom, 18)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onBegin)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - VisualEyes monogram with a periodic specular "glint"

/// The VisualEyes monogram with a soft light-sweep that travels diagonally across the
/// glyph every few seconds. The base mark sits slightly dimmed; a brighter, glowing copy
/// is revealed through a moving gradient band, so the glint reads clearly even though the
/// logo is white. Honours Reduce Motion (renders a static mark instead).
private struct GlintLogo: View {
    var width: CGFloat = 165

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 drives the band from fully off the left edge to fully off the right.
    @State private var sweep: CGFloat = 0
    /// false → true plays the entrance: huge + diagonally spun → settled at final size.
    @State private var entered = false

    private var mark: some View {
        Image("oops_logo").resizable().scaledToFit().frame(width: width)
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                mark
            } else {
                // Dimmed base mark.
                mark.opacity(0.7)

                // Bright, glowing copy revealed only where the moving band crosses.
                mark
                    .shadow(color: .white.opacity(0.95), radius: 11)
                    .shadow(color: .white.opacity(0.6), radius: 4)
                    .mask {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let band = w * 0.7
                            // Travel a little over two logo-widths so the band is on-screen
                            // for a good beat, then a short pause before the cycle repeats.
                            let travel = w * 2.2 + band
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white, location: 0.5),
                                    .init(color: .clear, location: 1.0),
                                ],
                                startPoint: .leading, endPoint: .trailing)
                                .frame(width: band, height: geo.size.height * 1.6)
                                .rotationEffect(.degrees(18))
                                .offset(x: -band + sweep * travel)
                                .frame(width: w, height: geo.size.height)
                        }
                    }
            }
        }
        .frame(width: width)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        // Entrance: start huge and spun about a diagonal axis, then shrink + spin to rest.
        .scaleEffect((reduceMotion || entered) ? 1 : 4)
        .rotation3DEffect(.degrees((reduceMotion || entered) ? 0 : 540),
                          axis: (x: 1, y: 1, z: 0))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2)) { entered = true }
            // Hold the glint until the entrance has settled, then loop it.
            withAnimation(.easeInOut(duration: 1.8).delay(1.4).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}

// MARK: - 02 · Home

struct HomeScreen: View {
    let onGenerate: () -> Void
    let onVisitOld: () -> Void

    var body: some View {
        ZStack {
            OopsPassthrough()
            HStack {
                Spacer()
                WorldWindow {
                    VStack {
                        Spacer()
                        HStack(spacing: 32) {
                            Button("Generate New", action: onGenerate)
                                .buttonStyle(OopsButton(fixedWidth: 302, fixedHeight: 75))
                            Button("Visit Old World", action: onVisitOld)
                                .buttonStyle(OopsButton(fixedWidth: 302, fixedHeight: 75))
                        }
                        .padding(.bottom, 54)
                    }
                }
                .frame(maxWidth: 980, maxHeight: 620)
                Spacer()
            }
            .padding(.horizontal, 60)

            VStack {
                Spacer()
                PageDots().padding(.bottom, 18)
            }
        }
    }
}

/// The framed "generated world" preview pane on Opening / Home. Uses `oops_meadow`
/// as a stand-in (the prototype's `villa.png` wasn't included in the asset bundle).
private struct WorldWindow<Overlay: View>: View {
    @ViewBuilder var overlay: Overlay
    init(@ViewBuilder overlay: () -> Overlay = { EmptyView() }) { self.overlay = overlay() }

    var body: some View {
        ZStack {
            Image("oops_meadow")
                .resizable()
                .scaledToFill()
            LinearGradient(colors: [.clear, .black.opacity(0.35)],
                           startPoint: .center, endPoint: .bottom)
            // VisualEyes monogram — centred over the world preview (Figma node 285:1442:
            // 233px wide in the 1392px card ≈ 16.7% → ~165pt here).
            GlintLogo()
            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: OopsGlass.radiusWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OopsGlass.radiusWindow, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 26)
    }
}

// MARK: - 03 / 04 · Declaration (Safety & Privacy)

/// 03 / 04 · Safety Declaration & Privacy Preferences (Figma nodes 46:1124 / 49:2173).
///
/// One frosted glass card, built from edge-pinned overlay layers (same pattern as the quiz):
///   • Back button   — top-leading circular glass control
///   • Content       — title + subtitle + the three circular-toggle statements
///   • CTA           — "I agree & continue" / "Start" pill, pinned bottom-centre
///
/// `requireAll` gates the CTA: Safety needs all three toggles ON; Privacy is optional (Start
/// is always enabled).
struct DeclarationScreen: View {
    let label: String
    let title: String
    let subtitle: String
    let items: [OopsContent.Statement]
    let cta: String
    @Binding var checks: [Bool]
    var requireAll: Bool = true   // true = all toggles required; false = no selection required
    let onCta: () -> Void
    var onBack: (() -> Void)? = nil

    private var canContinue: Bool {
        requireAll ? checks.allSatisfy { $0 } : true
    }

    // Frame height follows the Quiz card: a fixed height, capped to the available
    // viewport (mirrors QuizScreen.maxCardHeight / outerMargin) so the Safety,
    // Privacy and Quiz frames are all the same height.
    private let maxCardHeight: CGFloat = 760
    private let outerMargin: CGFloat = 20

    var body: some View {
      GeometryReader { geo in
        let cardHeight = min(maxCardHeight, geo.size.height - outerMargin * 2)
        ZStack {
            OopsPassthrough(dim: true)

            // Figma node 46:1124 stacks the screen vertically: a frosted content card
            // (back button → title → subtitle → statements) with the CTA pill BELOW it.
            // A VStack — not an overlay — keeps the button from ever overlapping the
            // statements, no matter how tall the copy runs.
            VStack(spacing: 34) {
                // 1 — Content (back button → title → subtitle → statements), sitting
                // directly on the single frosted window — no nested second-layer panel.
                VStack(alignment: .leading, spacing: 28) {
                    // Back button — top-leading, above the title (Figma 289:2111)
                    if let onBack {
                        backButton(action: onBack)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).oopsTitle(36)
                        Text(subtitle)
                            .oopsSub(18)
                            .foregroundStyle(.white.opacity(0.92))
                            // Reserve 2 lines on BOTH screens so the Safety intro (2 lines)
                            // and the shorter Privacy intro (1 line) push the statements to
                            // the same Y — keeps frame heights and bullet placement aligned.
                            .lineLimit(2, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 26) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            CheckStatement(head: item.head, text: item.text,
                                           checked: checks[i]) { checks[i].toggle() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 2 — CTA pill, centred BELOW the content (Figma 289:2130) — never overlaps
                Button(cta, action: onCta)
                    .buttonStyle(OopsButton(fixedWidth: 302, fixedHeight: 75))
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.2), value: canContinue)
            }
            .frame(width: 960)
            .padding(52)
            // Fixed card height matching the Quiz frame (content stays vertically centred).
            .frame(height: cardHeight)
            .oopsWindow()

            VStack { Spacer(); PageDots().padding(.bottom, 18) }
        }
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }

    /// Circular glass back button (Figma: 60×60 px → 44×44 pt), matching the quiz screen.
    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.20), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

// Note: the real screens float over a clear passthrough (the room) and inside a
// `.plain` window with no glass. Previews can't render the window/passthrough, so the
// gray fill below just stands in for the room to make the floating layout legible.

#Preview("Opening") {
    OpeningScreen(onBegin: {})
        .preferredColorScheme(.dark)
        .background(Color.gray.opacity(0.35))
}

#Preview("Home") {
    HomeScreen(onGenerate: {}, onVisitOld: {})
        .preferredColorScheme(.dark)
        .background(Color.gray.opacity(0.35))
}
 

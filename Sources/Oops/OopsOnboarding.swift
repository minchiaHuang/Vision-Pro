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
            // The four gold picture frames are split into their own transparent layers
            // (over a frames-removed background) so each can bob gently in place.
            FloatingFramesImage()
                .frame(maxWidth: 980, maxHeight: 620)
                .clipShape(RoundedRectangle(cornerRadius: OopsGlass.radiusWindow, style: .continuous))

            VStack {
                Spacer()
                Text("Tap anywhere to begin")
                    .oopsSub(20)
                    .foregroundStyle(.black)
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

// MARK: - Opening home image with gently floating picture frames

/// The opening "generated world" image. The source artwork (`home7`) had its four gold
/// picture frames cut out into separate full-canvas transparent layers (`oops_home_f0…f3`)
/// sitting over a frames-removed background (`oops_home_bg`). Because every layer shares the
/// same dimensions and the same `scaledToFill` geometry, they register pixel-perfectly; a
/// small per-frame vertical `offset` then makes each frame bob slightly in place.
///
/// Each frame uses a slightly different amplitude and period so they drift out of phase for
/// an organic float. Honours Reduce Motion (renders static).
private struct FloatingFramesImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    /// Frame layers, top-left · lower-left · top-right · mid-right.
    private let layers = ["oops_home_f0", "oops_home_f1", "oops_home_f2", "oops_home_f3"]
    private let amplitudes: [CGFloat] = [12, 14, 11, 13]
    private let periods: [Double] = [2.8, 3.4, 3.0, 3.6]

    var body: some View {
        ZStack {
            Image("oops_home_bg")
                .resizable()
                .scaledToFill()

            ForEach(layers.indices, id: \.self) { i in
                Image(layers[i])
                    .resizable()
                    .scaledToFill()
                    .offset(y: reduceMotion ? 0 : (bob ? -amplitudes[i] : amplitudes[i]))
                    .animation(reduceMotion ? nil
                               : .easeInOut(duration: periods[i]).repeatForever(autoreverses: true),
                               value: bob)
            }
        }
        .onAppear { bob = true }
    }
}

// MARK: - VisualEyes monogram with a periodic specular "glint"

/// The VisualEyes monogram with a particle-reveal entrance and a periodic specular "glint".
/// On appear, a cloud of soft white motes rushes inward and condenses while the glyph
/// resolves out of it; thereafter a brighter copy is swept by a moving gradient band so the
/// glint reads clearly even though the logo is white. Honours Reduce Motion (renders a
/// static mark, with no particles or sweep).
private struct GlintLogo: View {
    var width: CGFloat = 165

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 drives the band from fully off the left edge to fully off the right.
    @State private var sweep: CGFloat = 0
    /// 0 → 1 drives the particle reveal: the cloud flies in and the mark coalesces from it.
    @State private var reveal: CGFloat = 0
    /// 0 → 1 drives the mark's own fade-in. Kept separate from `reveal` so the glyph can
    /// resolve more slowly than the (snappier) particle cloud.
    @State private var logoIn: CGFloat = 0

    /// Number of motes in the reveal cloud.
    private let particleCount = 90

    private var mark: some View {
        Image("oops_logo").resizable().scaledToFit().frame(width: width)
    }

    /// The two stacked marks — a dimmed base plus a glowing copy that the glint band sweeps.
    private var marks: some View {
        ZStack {
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

    var body: some View {
        Group {
            if reduceMotion {
                mark
            } else {
                marks
                    // The mark resolves out of the cloud: invisible until the motes begin
                    // to condense, then settling to full opacity and size.
                    .opacity(logoResolve)
                    .scaleEffect(0.92 + 0.08 * logoResolve)
                    // Glowing particle cloud, drawn on top and allowed to spill well beyond
                    // the mark so the motes can fly in from outside it.
                    .overlay { particles }
            }
        }
        .frame(width: width)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.5)) { reveal = 1 }
            // Fade the glyph in slowly, starting once the cloud has begun to condense.
            withAnimation(.easeInOut(duration: 2.8).delay(0.5)) { logoIn = 1 }
            // Hold the glint until the fade-in has settled, then loop it.
            withAnimation(.easeInOut(duration: 1.8).delay(3.4).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }

    /// How resolved the mark is (0 → invisible, 1 → fully present). Lags the particle
    /// cloud so the glyph appears to coalesce from it.
    private var logoResolve: CGFloat {
        reduceMotion ? 1 : logoIn
    }

    // MARK: Particle cloud

    /// A field of soft white motes that start scattered around the mark and fly inward,
    /// fading out as they arrive — leaving the resolved logo behind. The drawing is a pure
    /// function of `reveal`, so SwiftUI redraws it on each animation frame.
    private var particles: some View {
        Canvas { ctx, size in
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.4))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = width * 0.5                       // logo half-width reference
                for i in 0..<particleCount {
                    let delay = hash(i, 0) * 0.4
                    let t = smoothstep(0, 1, (reveal - delay) / max(0.0001, 1 - delay))
                    if t <= 0 { continue }

                    // Home: somewhere within the mark's box. Start: scattered outward.
                    let home = CGPoint(x: center.x + (hash(i, 1) * 2 - 1) * r * 0.85,
                                       y: center.y + (hash(i, 2) * 2 - 1) * r * 0.85)
                    let scatter = 1.0 + hash(i, 3) * 1.2
                    let start = CGPoint(x: home.x + (hash(i, 4) * 2 - 1) * r * scatter,
                                        y: home.y + (hash(i, 5) * 2 - 1) * r * scatter)
                    let pos = CGPoint(x: start.x + (home.x - start.x) * t,
                                      y: start.y + (home.y - start.y) * t)

                    // Fade in as it sets off, fade out as it reaches home.
                    let op = smoothstep(0, 0.18, t) * (1 - smoothstep(0.7, 1, t))
                    if op <= 0.01 { continue }

                    let s = 1.6 + hash(i, 6) * 3.0
                    let rect = CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s)
                    layer.fill(Path(ellipseIn: rect), with: .color(.white.opacity(op)))
                }
            }
        }
        // Spill beyond the mark (symmetrically, so the cloud stays centred on the glyph).
        .padding(-width * 1.4)
        .allowsHitTesting(false)
    }

    /// Smooth Hermite interpolation between two edges, clamped to [0, 1].
    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Deterministic 0…1 pseudo-random keyed by mote index `i` and channel `k`, so the cloud
    /// is identical on every redraw. Integer-only (no trig / Foundation dependency).
    private func hash(_ i: Int, _ k: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64((i &* 73856093) ^ (k &* 19349663) ^ 0x9E3779B9))
        x ^= x >> 16; x &*= 0x7feb352d
        x ^= x >> 15; x &*= 0x846ca68b
        x ^= x >> 16
        return CGFloat(x & 0xFFFFFF) / CGFloat(0xFFFFFF)
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

            // Figma node 46:1124. A single vertical stack: the header (back button → title →
            // subtitle) hugs the TOP, then a fixed gap, then the three statements, then a
            // flexible Spacer, then the CTA pill. Because the Spacer can never collapse below
            // its minimum, the button can NOT overlap the statements no matter how tall the
            // copy runs — yet on both the Safety and Privacy screens it still settles to the
            // same bottom-centre spot (the Spacer absorbs the difference in copy height).
            VStack(spacing: 0) {
                // 1 — Header (back button → title → subtitle), top-leading.
                VStack(alignment: .leading, spacing: 28) {
                    // Back button — top-leading, above the title (Figma 289:2111).
                    // Equal top/bottom padding so the arrow sits evenly between the card
                    // edge and the title.
                    if let onBack {
                        backButton(action: onBack)
                            .padding(.vertical, 16)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Gap between the header and the bullet points — pushes the statements down.
                Color.clear.frame(height: 56)

                // 2 — The three circular-toggle statements, top-leading.
                VStack(spacing: 18) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        CheckStatement(head: item.head, text: item.text,
                                       checked: checks[i]) { checks[i].toggle() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Flexible gap: grows to push the CTA toward the bottom, but never shrinks
                // past 24pt — this minimum is what guarantees the pill clears the copy.
                Spacer(minLength: 24)

                // 3 — CTA pill, bottom-centre (Figma 289:2130). Sized 258×65 — another 5%
                // down from the prior 272×68 — for reliable clearance on the tall Safety screen.
                Button(cta, action: onCta)
                    .buttonStyle(OopsButton(fixedWidth: 258, fixedHeight: 65))
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.2), value: canContinue)
            }
            .frame(width: 960)
            .padding(52)
            // Fixed card height matching the Quiz frame.
            .frame(height: cardHeight)
            .oopsWindow()

            VStack { Spacer(); PageDots().padding(.bottom, 18) }
        }
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }

    /// Bare back chevron — no glass circle. Left-aligned with the title/body copy, with a
    /// 44pt hit target retained for comfortable tapping.
    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                // 10% + 5% larger than the original 16pt glyph.
                .font(.system(size: 18.48, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
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
 

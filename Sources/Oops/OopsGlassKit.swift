import SwiftUI

/// Design system for the "Oops" visionOS glass flow.
/// Tokens reconstructed from the prototype's `styles.css` (dark translucent glass,
/// graded-white text, pill buttons, vertical glass bars). Self-contained so the warm
/// `VATheme` look stays untouched — the two flows live side by side under the Dev Menu.
enum OopsGlass {
    // Graded white text ladder (DS: primary .96 / secondary .55 / tertiary .25).
    static let label1 = Color.white.opacity(0.96)
    static let label2 = Color.white.opacity(0.55)
    static let label3 = Color.white.opacity(0.25)

    static let systemBlue = Color(red: 0.039, green: 0.518, blue: 1.0) // #0A84FF

    // Corner radii (DS: window 46, card 20, bar 42.7).
    static let radiusWindow: CGFloat = 46
    static let radiusCard: CGFloat = 28
    static let radiusBar: CGFloat = 42.7
}

// MARK: - Passthrough background

/// The room "passthrough" behind every glass screen. Falls back to a dark gradient
/// if the asset is missing so the flow always renders.
struct OopsPassthrough: View {
    var dim: Bool = false
    var body: some View {
        #if os(visionOS)
        // Vision Pro: the window glass already frosts the real room behind it, so this
        // layer stays transparent — no fake passthrough photo. The glass panels float
        // over the actual environment. `dim` keeps a faint scrim for text legibility.
        Color.clear
            .overlay { if dim { Color.black.opacity(0.18) } }
            .ignoresSafeArea()
        #else
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.05)
            Image("oops_passthrough")
                .resizable()
                .scaledToFill()
            if dim { Color.black.opacity(0.28) }
        }
        .ignoresSafeArea()
        #endif
    }
}

// MARK: - Glass surfaces

private struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var strongShadow: Bool
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(strongShadow ? 0.30 : 0.22),
                    radius: strongShadow ? 40 : 26, y: strongShadow ? 30 : 14)
            .preferredColorScheme(.dark)
    }
}

extension View {
    /// Heavy frosted "window" pane (Opening / Home / Quiz).
    func oopsWindow(cornerRadius: CGFloat = OopsGlass.radiusWindow) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, strongShadow: true))
    }
    /// Lighter "card" pane (declarations / preview / dialog).
    func oopsCard(cornerRadius: CGFloat = OopsGlass.radiusCard) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, strongShadow: false))
    }
}

// MARK: - Circular back control

/// Large circular glass "back" control — the label for the Quiz / Declaration back buttons,
/// matching the round glass look visionOS gives the world screens' ornament buttons. The filled
/// glass disc + `contentShape(Circle())` give a solid, reliable tap target: a bare transparent
/// chevron hit-tests unreliably on visionOS (its empty area doesn't always register the tap).
/// `diameter` / `glyph` are exposed so the size is easy to tune.
struct OopsBackCircleLabel: View {
    var diameter: CGFloat = 60
    var glyph: CGFloat = 20

    var body: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(.ultraThinMaterial, in: Circle())
            .background(Color.white.opacity(0.06), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .contentShape(Circle())
    }
}

// MARK: - Text styles

extension View {
    /// `.h-title` — 36 / 700, primary white.
    func oopsTitle(_ size: CGFloat = 34) -> some View {
        self.font(.system(size: size, weight: .bold))
            .tracking(-0.3)
            .foregroundStyle(OopsGlass.label1)
    }
    /// `.h-sub` — 22 / 500, secondary white.
    func oopsSub(_ size: CGFloat = 20) -> some View {
        self.font(.system(size: size, weight: .medium))
            .foregroundStyle(OopsGlass.label2)
    }
}

// MARK: - Pill button

/// Glass pill CTA (`.av-btn`). `ghost` = fainter fill with a hairline ring.
struct OopsButton: ButtonStyle {
    var ghost: Bool = false
    var minWidth: CGFloat = 250
    /// When set, the pill is laid out at this exact size (capsule included) instead of
    /// sizing to its label + horizontal padding. Used to keep the primary CTAs a uniform
    /// 302×75 across the Home / Safety / Privacy screens.
    var fixedWidth: CGFloat? = nil
    var fixedHeight: CGFloat? = nil
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            // VisualEyes `.gbtn`: Roboto 500 / 31px → ~24pt in this window, light tracking.
            .font(.system(size: 24, weight: .medium))
            .tracking(0.2)
            .foregroundStyle(.white)

        return Group {
            if let fixedWidth {
                label.frame(width: fixedWidth, height: fixedHeight ?? 64)
            } else {
                label
                    .frame(minWidth: minWidth)
                    .frame(height: fixedHeight ?? 64)
                    .padding(.horizontal, 36)
            }
        }
            // `.gbtn` fill: a white→gray glass sheen (rgba(255,255,255,.42) → rgba(120,120,120,.42))
            // layered over the system blur, rather than a flat tint.
            .background(
                LinearGradient(
                    colors: ghost
                        ? [Color.white.opacity(0.12), Color(white: 0.47).opacity(0.16)]
                        : [Color.white.opacity(0.42), Color(white: 0.47).opacity(0.42)],
                    startPoint: UnitPoint(x: 0.02, y: 0.0),
                    endPoint:   UnitPoint(x: 0.98, y: 1.0)))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(ghost ? 0.25 : 0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { ButtonClick.play() }
            }
    }
}

// MARK: - Frosted text field / textarea

/// `.quiz-input` — frosted single-line field or multi-line textarea. Shared by the quiz
/// and the reflection screens.
struct OopsField: View {
    @Binding var text: String
    let placeholder: String
    let multiline: Bool

    var body: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(.vertical, 22)
            } else {
                TextField(placeholder, text: $text)
                    .frame(height: 80)
            }
        }
        .font(.system(size: 23))
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .tint(.white)
    }
}

// MARK: - Vertical glass bars

/// Generic vertical glass bar (`.glass-bar`) hosting circular controls.
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 16) { content }
            .padding(.vertical, 15)
            .padding(.horizontal, 11)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: OopsGlass.radiusBar, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OopsGlass.radiusBar, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    }
}

/// Circular glass control used inside the bars (`.bar-btn`).
struct BarButton: View {
    let systemImage: String
    var action: () -> Void = {}
    var body: some View {
        Button { ButtonClick.play(); action() } label: {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// In-world control bar: avatar + leave + reset.
struct WorldBar: View {
    var onClose: () -> Void = {}
    var onReset: () -> Void = {}
    var body: some View {
        GlassBar {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.69, blue: 0.48),
                                              Color(red: 0.48, green: 0.61, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .frame(width: 56, height: 56)
            BarButton(systemImage: "xmark", action: onClose)
            BarButton(systemImage: "arrow.clockwise", action: onReset)
        }
    }
}

// MARK: - AI assistant orb (white glass, manual voice states)

/// White-glass assistant sphere mirroring the prototype's `.ai-orb`. Tapping cycles
/// idle → listening → thinking → speaking → idle (no real audio in this pass).
struct GlassOrb: View {
    var size: CGFloat = 56
    enum OrbState { case idle, listening, thinking, speaking }
    @State private var state: OrbState = .idle
    @State private var breathe = false
    @State private var spin = false

    private var orb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.96), .white.opacity(0.55),
                             .white.opacity(0.18), .white.opacity(0.06)],
                    center: .init(x: 0.36, y: 0.30),
                    startRadius: 1, endRadius: size * 0.42)
            )
            .frame(width: size * 0.78, height: size * 0.78)
            .shadow(color: .white.opacity(state == .idle ? 0.35 : 0.6), radius: state == .idle ? 10 : 18)
    }

    var body: some View {
        ZStack {
            // soft halo
            Circle().fill(.white.opacity(0.18)).blur(radius: 10)
                .frame(width: size, height: size)
                .scaleEffect(breathe ? 1.12 : 1.0)

            // listening rings
            if state == .listening {
                ForEach(0..<2, id: \.self) { i in
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2)
                        .frame(width: size * 0.78, height: size * 0.78)
                        .scaleEffect(breathe ? 2.6 : 1.0)
                        .opacity(breathe ? 0 : 0.7)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.6), value: breathe)
                }
            }

            // thinking shimmer ring
            if state == .thinking {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size * 0.88, height: size * 0.88)
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }

            orb.scaleEffect(scaleForState)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { advance() }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityLabel("Assistant")
    }

    private var scaleForState: CGFloat {
        switch state {
        case .idle:      return breathe ? 1.05 : 1.0
        case .listening: return breathe ? 1.09 : 1.0
        case .thinking:  return 1.0
        case .speaking:  return breathe ? 1.12 : 1.0
        }
    }

    private func advance() {
        switch state {
        case .idle: state = .listening
        case .listening:
            state = .thinking
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                if state == .thinking { state = .speaking }
            }
        case .thinking, .speaking: state = .idle
        }
    }
}

// MARK: - Progress indicators

/// `.page-dots` — intentionally empty. The prototype drew a dot + long home-pill capsule
/// near the bottom, but on visionOS/iPad both visually duplicate the system window
/// grabber bar, so nothing is rendered here.
struct PageDots: View {
    var body: some View { EmptyView() }
}

// MARK: - Checkbox statement

/// `.statement` — capsule toggle + heading + body, used on the declaration screens
/// (Safety Declaration / Privacy Preferences — Figma nodes 46:1124 / 288:1907).
struct CheckStatement: View {
    let head: String
    let text: String
    let checked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            toggle
                // Nudge down so the toggle aligns with the heading's first line.
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 9) {
                Text(head)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OopsGlass.label1)
                Text(text)
                    .font(.system(size: 17, weight: .regular))
                    // Body copy reads bright on the frosted card (HTML `.row-body` ≈ white 0.96).
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(2)
                    // Reserve 3 lines (the longest body) for every row so each statement
                    // occupies an identical slot — bullet headings line up across the
                    // Safety and Privacy screens and both frames end up the same height.
                    .lineLimit(3, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        // The whole row is the tap target — not just the small pill — so every
        // statement toggles reliably (pinch/tap can be imprecise on a tiny pill).
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .animation(.easeInOut(duration: 0.2), value: checked)
    }

    /// "Checkbox" pill from VisualEyes Screens.html (`.pill.check`): a 36×30 glass pill.
    /// OFF = frosted glass gradient, empty. ON = bright white fill with a soft outer
    /// glow (no checkmark — the filled pill alone signals the selected state).
    private var toggle: some View {
        Capsule()
            .fill(
                checked
                    ? LinearGradient(
                        colors: [Color.white.opacity(0.95),
                                 Color(red: 0.92, green: 0.92, blue: 0.94).opacity(0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(
                        colors: [Color.white.opacity(0.42),
                                 Color(white: 0.47, opacity: 0.42)],
                        startPoint: UnitPoint(x: 0.10, y: 0.05),
                        endPoint:   UnitPoint(x: 0.90, y: 0.95)))
            .overlay(Capsule().strokeBorder(.white.opacity(checked ? 0.0 : 0.55), lineWidth: 1.5))
            .shadow(color: checked ? Color.white.opacity(0.55) : .black.opacity(0.18),
                    radius: checked ? 7 : 4, y: checked ? 0 : 1)
            .frame(width: 36, height: 30)
            .animation(.easeInOut(duration: 0.2), value: checked)
    }
}

// MARK: - visionOS toggle + preference row (Privacy Preferences)

/// visionOS-style green pill toggle (design `Toggle`). 64×38 capsule, #32D74B when on /
/// neutral grey when off, with a 30pt white knob that slides to the active edge.
struct OopsToggle: View {
    var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Color(.sRGB, red: 50.0 / 255, green: 215.0 / 255, blue: 75.0 / 255, opacity: 1)
                     : Color(white: 0.47, opacity: 0.5))
            .frame(width: 64, height: 38)
            .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.20 : 0.25), lineWidth: 1))
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.30), radius: 2.5, y: 2)
                    .padding(.horizontal, 4)
            }
            .animation(.easeInOut(duration: 0.2), value: on)
    }
}

/// Privacy preference row — same heading+body block as `CheckStatement` but with the green
/// toggle on the RIGHT (design `PrefRow`). The whole row is the tap target so it toggles
/// reliably (pinch/tap can be imprecise on the small switch).
struct PrefToggleRow: View {
    let head: String
    let text: String
    let on: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text(head)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(OopsGlass.label1)
                Text(text)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(2)
                    .lineLimit(3, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            OopsToggle(on: on)
                // Align the switch with the heading's first line.
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .animation(.easeInOut(duration: 0.2), value: on)
    }
}

// MARK: - Spinner

/// `.spinner` — indeterminate ring used on the generating screen.
struct OopsSpinner: View {
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.85)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: 60, height: 60)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
            .overlay(
                Circle().stroke(.white.opacity(0.2), lineWidth: 4).frame(width: 60, height: 60))
    }
}

// MARK: - Confirmation dialog

/// `.overlay` + `.dialog` — the "Are you sure?" sheet shown over the quiz.
struct OopsDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(spacing: 0) {
                Text(title).oopsTitle(30)
                    .padding(.bottom, 16)
                Text(message)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(OopsGlass.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 30)
                VStack(spacing: 12) {
                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(OopsButton(ghost: true, minWidth: 300))
                    Button("Never mind…") { ButtonClick.play(); onCancel() }
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .underline()
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 48)
            .padding(.bottom, 36)
            .frame(width: 540)
            .oopsCard(cornerRadius: 42)
        }
    }
}

// MARK: - Previews

#Preview("Passthrough") { OopsPassthrough() }
#Preview("Passthrough – dim") { OopsPassthrough(dim: true) }

#Preview("OopsButton – solid") {
    Button("Generate New") {}
        .buttonStyle(OopsButton())
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("OopsButton – ghost") {
    Button("Visit Old World") {}
        .buttonStyle(OopsButton(ghost: true))
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("OopsField – single") {
    OopsField(text: .constant(""), placeholder: "Your answer…", multiline: false)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("OopsField – multi") {
    OopsField(text: .constant("This is a longer answer spanning multiple lines."),
              placeholder: "Reflect…", multiline: true)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("GlassBar + BarButton") {
    GlassBar {
        BarButton(systemImage: "xmark")
        BarButton(systemImage: "arrow.clockwise")
    }
    .preferredColorScheme(.dark)
}

#Preview("WorldBar") {
    WorldBar()
        .preferredColorScheme(.dark)
}

#Preview("GlassOrb") {
    GlassOrb(size: 72)
        .padding(40)
        .background(Color.black)
}

#Preview("CheckStatement – unchecked") {
    CheckStatement(head: "I understand",
                   text: "This experience may be emotionally intense.",
                   checked: false, onToggle: {})
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("CheckStatement – checked") {
    CheckStatement(head: "I understand",
                   text: "This experience may be emotionally intense.",
                   checked: true, onToggle: {})
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("OopsSpinner") {
    OopsSpinner()
        .padding(40)
        .background(Color.black)
}

#Preview("OopsDialog") {
    OopsDialog(title: "Are you sure?",
               message: "Your progress will be lost forever.",
               confirmTitle: "Yes, start over",
               onConfirm: {}, onCancel: {})
        .background(Color.gray.opacity(0.3))
        .preferredColorScheme(.dark)
}

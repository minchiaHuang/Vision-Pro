import SwiftUI

/// Visual design system for the warm, glassy "Visiting Artisan" look.
/// Skin-only: colors, type styles, pill buttons, warm background, and the orb.
enum VATheme {
    static let amber     = Color(red: 0.910, green: 0.663, blue: 0.361) // #E8A95C
    static let amberDeep = Color(red: 0.784, green: 0.533, blue: 0.220) // #C88838
    static let amberGlow = Color(red: 1.000, green: 0.878, blue: 0.690) // #FFE0B0
    static let onAmber   = Color(red: 0.157, green: 0.098, blue: 0.039) // #28190A

    // Warm "egg-yolk" cream background (light). Dark mode shifts to a deep warm tone.
    static let warmTop    = Color(red: 0.988, green: 0.937, blue: 0.816) // #FCEFD0
    static let warmBottom = Color(red: 0.965, green: 0.890, blue: 0.745) // #F6E3BE
    static let warmTopDark    = Color(red: 0.102, green: 0.078, blue: 0.059) // #1A1410
    static let warmBottomDark = Color(red: 0.039, green: 0.031, blue: 0.024) // #0A0806
}

// MARK: - Type styles

/// Small, uppercase, tracked-out eyebrow label (e.g. "VISITING ARTISAN").
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(3)
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Large, thin SF Pro title that replaces the previous serif headline.
    func vaLargeThinTitle(size: CGFloat = 40) -> some View {
        self.font(.system(size: size, weight: .regular))
            .tracking(-0.4)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Buttons

/// Primary CTA: amber gradient capsule with dark label.
struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(VATheme.onAmber)
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .frame(minHeight: 56)
            .background(
                LinearGradient(colors: [VATheme.amber, VATheme.amberDeep],
                               startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: VATheme.amber.opacity(0.35), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary: translucent glass capsule.
struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.vertical, 16)
            .padding(.horizontal, 28)
            .frame(minHeight: 56)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Warm background

/// Warm paper gradient placed behind the whole app.
struct WarmBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [VATheme.warmTopDark, VATheme.warmBottomDark]
                    : [VATheme.warmTop, VATheme.warmBottom],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [VATheme.amber.opacity(scheme == .dark ? 0.18 : 0.28), .clear],
                center: .init(x: 0.5, y: 0.28),
                startRadius: 0, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Orb

/// Glowing amber orb used on splash and loading ("Weaving") screens, and as the
/// world's voice-companion mascot. `isSpeaking` makes it breathe stronger and
/// glow warmer (the guide is talking); `isListening` adds a cool cyan ring (the
/// guide is hearing the visitor). Both default off, so existing call sites are
/// unaffected.
struct OrbView: View {
    var size: CGFloat = 180
    var isSpeaking: Bool = false
    var isListening: Bool = false
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        ZStack {
            // Listening ring — cool cyan, only while hearing the visitor.
            Circle()
                .strokeBorder(Color.cyan.opacity(isListening ? 0.8 : 0), lineWidth: 2)
                .frame(width: size * 1.45, height: size * 1.45)
                .scaleEffect(isListening ? (pulse ? 1.06 : 0.98) : 1.0)
                .animation(.easeInOut(duration: 0.5), value: isListening)

            Circle()
                .strokeBorder(VATheme.amber.opacity(0.35), lineWidth: 0.5)
                .frame(width: size * 1.45, height: size * 1.45)
                .rotationEffect(.degrees(spin ? 360 : 0))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [VATheme.amberGlow, VATheme.amber, VATheme.amberDeep],
                        center: .init(x: 0.45, y: 0.4),
                        startRadius: 2, endRadius: size * 0.62
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: VATheme.amber.opacity(isSpeaking ? 0.7 : 0.45),
                        radius: isSpeaking ? 56 : 40)
                .scaleEffect(pulse ? (isSpeaking ? 1.12 : 1.04) : 1.0)
                .animation(.easeInOut(duration: 0.4), value: isSpeaking)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

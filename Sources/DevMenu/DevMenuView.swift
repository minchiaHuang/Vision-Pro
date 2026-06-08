import SwiftUI

// ⚠️ DEV ONLY — in-app launcher shown at app start while features are still being
// built. Lists each testable feature as a button; tapping opens it full-screen
// with a back button to return here. Replace the root with `RootView()` (or gate
// this behind a build flag) before shipping.

/// One testable feature reachable from the dev menu.
enum DevFeature: String, Identifiable, CaseIterable {
    case oops
    case voice
    case splat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oops:  return "Oops Flow"
        case .voice: return "Voice — Speech Test"
        case .splat: return "Splat — 6DoF Walkthrough"
        }
    }

    var subtitle: String {
        switch self {
        case .oops:  return "visionOS glass · onboarding → quiz → world"
        case .voice: return "Tap the orb to talk · ASR / LLM / TTS"
        case .splat: return "Generate or open a World Labs splat"
        }
    }

    var systemImage: String {
        switch self {
        case .oops:  return "rectangle.stack.badge.play"
        case .voice: return "waveform"
        case .splat: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// Features that embed their own `NavigationStack` provide their own back
    /// chrome, so the container hides its floating back button to avoid stacking
    /// two back affordances. The oops flow surfaces its own in-card back button,
    /// so it also opts out of the floating "Back to menu" chevron on every platform.
    var providesOwnNavigation: Bool {
        switch self {
        case .oops:
            return true
        case .splat:
            // splat embeds its own NavigationStack on iPad; visionOS has no splat
            // navigation, so it keeps the floating button there.
            #if os(visionOS)
            return false
            #else
            return true
            #endif
        case .voice:
            return false
        }
    }
}

/// The launcher screen: a vertical list of feature buttons.
struct DevMenuView: View {
    @Environment(AppState.self) private var appState

    /// Presented feature lives in `AppState` (not local `@State`) so the Oops splat
    /// world can dismiss + reopen this window without losing the user's place.
    private var activeBinding: Binding<DevFeature?> {
        Binding(get: { appState.devActiveFeature },
                set: { appState.devActiveFeature = $0 })
    }

    var body: some View {
        ZStack {
            // Hide the menu (and its warm background) while a feature is presented full
            // screen, so transparent features — the Oops passthrough screens — reveal the
            // real room behind, not this cream background.
            if appState.devActiveFeature == nil {
            WarmBackground()

            ZoomableContent {
                VStack(spacing: 24) {
                    Eyebrow("Dev Menu")

                    Text("Pick a feature to test")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.black)

                    VStack(spacing: 14) {
                        ForEach(DevFeature.allCases) { feature in
                            Button { appState.devActiveFeature = feature } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: feature.systemImage)
                                        .font(.title3)
                                        .frame(width: 32)
                                        .foregroundStyle(VATheme.amber)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(feature.title)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(.black)
                                        Text(feature.subtitle)
                                            .font(.system(size: 14))
                                            .foregroundStyle(.black.opacity(0.5))
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundStyle(.black.opacity(0.4))
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Explicit light fill on visionOS so the cards read lighter
                                // than the cream (matching iPad), instead of being darkened
                                // by glass vibrancy over the passthrough room.
                                #if os(visionOS)
                                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                                #else
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                #endif
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 480)
                }
                .padding(40)
            }
            }
        }
        .fullScreenCover(item: activeBinding) { feature in
            DevFeatureContainer(feature: feature) { appState.devActiveFeature = nil }
                .environment(appState)
        }
        // Warm golden look (matches the "Weaving" loading screen): force light so
        // `WarmBackground` uses its cream gradient + amber glow and text/material
        // contrast flip to suit it. The Oops flow re-asserts `.dark` for its glass.
        .preferredColorScheme(.light)
    }
}

/// Hosts one feature full-screen with a floating back button to the menu.
private struct DevFeatureContainer: View {
    let feature: DevFeature
    let onClose: () -> Void
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .topLeading) {
            content

            // Features with their own navigation (e.g. splat) surface their own
            // back button, so skip the floating one to avoid two stacked backs.
            if !feature.providesOwnNavigation {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 16)
                .accessibilityLabel("Back to menu")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feature {
        case .oops:
            // The visionOS glass prototype flow (own coordinator + screen state).
            OopsFlowView()
        case .voice:
            VoiceTestView()
        case .splat:
            SplatLibraryView(onClose: onClose)
        }
    }
}

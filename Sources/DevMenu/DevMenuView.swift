import SwiftUI

// ⚠️ DEV ONLY — in-app launcher shown at app start while features are still being
// built. Lists each testable feature as a button; tapping opens it full-screen
// with a back button to return here. Replace the root with `RootView()` (or gate
// this behind a build flag) before shipping.

/// One testable feature reachable from the dev menu.
enum DevFeature: String, Identifiable, CaseIterable {
    case full
    case world
    case voice
    case usdz
    case splat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full:  return "Full Flow"
        case .world: return "World — Enter Directly"
        case .voice: return "Voice — Speech Test"
        case .usdz:  return "USDZ — Model Viewer"
        case .splat: return "Splat — 6DoF Walkthrough"
        }
    }

    var subtitle: String {
        switch self {
        case .full:  return "splash → quiz → world"
        case .world: return "Default world, skips the quiz"
        case .voice: return "Tap the orb to talk · ASR / LLM / TTS"
        case .usdz:  return "RealityKit USDZ, first person"
        case .splat: return "World Labs Gaussian splat"
        }
    }

    var systemImage: String {
        switch self {
        case .full:  return "sparkles"
        case .world: return "globe.asia.australia"
        case .voice: return "waveform"
        case .usdz:  return "cube"
        case .splat: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// The launcher screen: a vertical list of feature buttons.
struct DevMenuView: View {
    @Environment(AppState.self) private var appState
    @State private var active: DevFeature?

    var body: some View {
        ZStack {
            WarmBackground()

            VStack(spacing: 24) {
                Eyebrow("Dev Menu")

                Text("Pick a feature to test")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)

                VStack(spacing: 14) {
                    ForEach(DevFeature.allCases) { feature in
                        Button { active = feature } label: {
                            HStack(spacing: 16) {
                                Image(systemName: feature.systemImage)
                                    .font(.title3)
                                    .frame(width: 32)
                                    .foregroundStyle(VATheme.amber)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(feature.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 480)
            }
            .padding(40)
        }
        .fullScreenCover(item: $active) { feature in
            DevFeatureContainer(feature: feature) { active = nil }
                .environment(appState)
        }
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

            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("Back to menu")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feature {
        case .full:
            // Fresh start each time the full flow is opened.
            RootView().onAppear { appState.restart() }
        case .world:
            WorldView().onAppear { appState.loadDefaultWorldForTesting() }
        case .voice:
            VoiceTestView()
        case .usdz:
            USDZTestView()
        case .splat:
            SplatSpikeView()
        }
    }
}

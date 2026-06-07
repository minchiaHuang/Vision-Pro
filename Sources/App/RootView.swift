import SwiftUI

/// Switches screens from the current app phase.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if appState.phase != .world {
                WarmBackground()
            }
            switch appState.phase {
            case .splash:
                SplashView()
            case .quiz:
                QuizView()
            case .loading:
                LoadingView()
            case .world:
                WorldView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.phase)
    }
}

/// Opening screen.
struct SplashView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 30) {
            OrbView(size: 120)

            VStack(spacing: 16) {
                Eyebrow("Visiting Artisan")

                Text("A world, woven for who\nyou are right now.")
                    .vaLargeThinTitle(size: 38)

                Text("Five soft questions. Then an immersive place, arranged from your own shape.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Begin") {
                appState.phase = .quiz
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
        .frame(maxWidth: 520)
        .padding(32)
    }
}

/// Short transition while the preset world is resolved.
struct LoadingView: View {
    @Environment(AppState.self) private var appState

    private var weavingCopy: String {
        switch appState.answers.hope {
        case "people":  return "Drawing the warmth of others\ninto your world."
        case "explore": return "Opening a horizon\nyou haven't yet seen."
        case "stable":  return "Laying down something\nyou can return to."
        default:        return "Shaping a world\nthat fits the shape of you."
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            OrbView(size: 180)

            VStack(spacing: 10) {
                Eyebrow("Weaving")

                Text(weavingCopy)
                    .vaLargeThinTitle(size: 26)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }
}

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
            case .error:
                ErrorView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.phase)
    }
}

/// Opening screen.
struct SplashView: View {
    @Environment(AppState.self) private var appState
    /// Looping ambient bed for the intro screen; stops when leaving for the quiz.
    @State private var ambience = IntroAmbiencePlayer()

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
        .onAppear { ambience.start() }
        .onDisappear { ambience.stop() }
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

/// Shown when world generation fails or times out. Offers to retry the same
/// generation, or to start over from the splash. Background comes from
/// `RootView`'s `WarmBackground` (any non-world phase), so this view is content-only.
struct ErrorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 30) {
            OrbView(size: 120)

            VStack(spacing: 16) {
                Eyebrow("Something slipped")

                Text(appState.loadError ?? "We couldn't finish weaving your world.")
                    .vaLargeThinTitle(size: 28)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                Button("Try again") {
                    appState.retryWorldGeneration()
                }
                .buttonStyle(PrimaryPillButtonStyle())

                Button("Back to start") {
                    appState.restart()
                }
                .buttonStyle(SecondaryPillButtonStyle())
            }
        }
        .frame(maxWidth: 520)
        .padding(32)
    }
}

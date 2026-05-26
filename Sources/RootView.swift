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
    @State private var showWorldLabs = false

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

            Button("Experimental: World Labs") {
                showWorldLabs = true
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520)
        .padding(32)
        .sheet(isPresented: $showWorldLabs) {
            WorldLabsTestView()
        }
    }
}

/// Short transition while the preset world is resolved.
struct LoadingView: View {
    @Environment(AppState.self) private var appState

    private var weavingCopy: String {
        let a = appState.answers
        let energyWord = a.energy < 0.35 ? "stillness"
            : (a.energy > 0.65 ? "bright energy" : "warm focus")
        let place: String
        switch a.week {
        case "sleep": place = "first light over the mountains"
        case "home":  place = "an open coastal horizon"
        case "exam", "focus": place = "a lamp-lit reading terrace"
        default: place = "a quiet forest stream"
        }
        return "Threading \(energyWord)\nthrough \(place)."
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

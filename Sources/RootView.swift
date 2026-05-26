import SwiftUI

/// Switches screens from the current app phase.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
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
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text("Visiting Artisan")
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)

                Text("A short ritual for finding your balance world.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Answer from instinct. Step into what steadies you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Begin") {
                appState.phase = .quiz
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

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
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                Text("Shaping your world...")
                    .font(.title3.weight(.semibold))

                Text("Finding the place your answers point toward.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

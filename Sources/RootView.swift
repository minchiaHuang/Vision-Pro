import SwiftUI

/// 根據 AppState.phase 切換畫面的狀態機。
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

/// 開場畫面。
struct SplashView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Text("Visiting Artisan")
                .font(.system(size: 40, weight: .semibold, design: .serif))
            Text("Who are you?")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Begin") {
                appState.phase = .quiz
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 12)
        }
        .padding()
    }
}

/// 「生成世界中」過場。
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Building your world…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

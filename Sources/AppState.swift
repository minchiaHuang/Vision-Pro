import SwiftUI
import Observation

/// Stages of the app flow.
enum AppPhase {
    case splash
    case quiz
    case loading
    case world
}

/// Global state (quiz answers, the resolved world, and the current step).
@Observable
final class AppState {
    var phase: AppPhase = .splash
    var answers = QuizAnswers()
    var world: World?

    /// Quiz done -> loading -> resolve the world -> enter the world.
    func finishQuiz() {
        phase = .loading
        Task {
            // Simulate the "generating world" transition (v2: this becomes a real API call).
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                self.world = WorldCatalog.resolve(from: self.answers)
                self.phase = .world
            }
        }
    }

    /// Restart from the beginning.
    func restart() {
        answers = QuizAnswers()
        world = nil
        phase = .splash
    }
}

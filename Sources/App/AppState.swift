import SwiftUI
import Observation
import UIKit

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

    /// Runtime panorama from World Labs (not a bundled asset). When set, the world
    /// views render this image instead of `world.imageName`.
    var generatedPano: UIImage?

    /// Remote (public CDN) `.spz` URL for the generated world's walkable 3D splat,
    /// plus its world id. Set when a World Labs world is generated; the world phase
    /// downloads the splat on demand when the user switches to "walkable".
    var generatedSplatURL: URL?
    var generatedWorldId: String?

    /// Hidden continuous scores (the bottom layer of research direction 6) and the world
    /// parameters they map to (direction 7). Computed and stored from Phase 3 on; the
    /// display layer consumes `worldParams` from Phase 2 on.
    var axisScores: AxisScores?
    var worldParams: WorldParams?

    /// Quiz done -> loading -> resolve the world -> enter the world.
    func finishQuiz() {
        phase = .loading
        Task {
            // Simulate the "generating world" transition (v2: this becomes a real API call).
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                // Research direction 6->7: compute the hidden continuous scores first,
                // then map them into world parameters.
                let scores = Scorer.score(self.answers)
                self.axisScores = scores
                self.worldParams = WorldMapper.map(scores)
                // title/blurb are derived from the archetype, keeping the overlay text
                // consistent with the USDZ scene.
                self.world = WorldCatalog.world(for: self.worldParams!.archetype)
                self.phase = .world
            }
        }
    }

    /// DEV ONLY — preload a neutral default world so the dev menu's "World" option
    /// can jump straight into `WorldView`, skipping the quiz.
    func loadDefaultWorldForTesting() {
        let scores = AxisScores.neutral
        axisScores = scores
        let params = WorldMapper.map(scores)
        worldParams = params
        world = WorldCatalog.world(for: params.archetype)
        phase = .world
    }

    /// Restart from the beginning.
    func restart() {
        answers = QuizAnswers()
        world = nil
        axisScores = nil
        worldParams = nil
        generatedPano = nil
        generatedSplatURL = nil
        generatedWorldId = nil
        phase = .splash
    }
}

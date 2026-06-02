import SwiftUI
import Observation
import UIKit

/// Stages of the app flow.
enum AppPhase {
    case splash
    case quiz
    case loading
    case world
    /// World generation failed or timed out; `ErrorView` offers retry / back-home.
    /// No associated value so `AppPhase` keeps its synthesized `Equatable`
    /// (needed by `RootView`'s `.animation(value:)`); the message lives in
    /// `AppState.loadError`.
    case error
}

/// Raised when world generation cannot finish in time. Kept tiny on purpose —
/// today's scoring is instant, so this only fires once the loading step becomes
/// a real (v2) network call that can hang.
struct WorldGenTimeout: Error {}

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

    /// Human-readable reason the world failed to generate, shown by `ErrorView`.
    /// `nil` whenever we are not in the `.error` phase.
    var loadError: String?

    /// How long world generation may run before we surface an error. Harmless
    /// today (scoring is instant); meaningful once loading becomes a real call.
    private let generationTimeout: Duration = .seconds(15)

    /// Quiz done -> loading -> resolve the world -> enter the world.
    func finishQuiz() {
        startWorldGeneration()
    }

    /// Re-run world generation after a failure (the `ErrorView` "try again").
    func retryWorldGeneration() {
        startWorldGeneration()
    }

    /// Drive the loading -> world (or -> error) transition. Both `finishQuiz`
    /// and `retryWorldGeneration` funnel through here so retry is just another
    /// attempt down the same path.
    private func startWorldGeneration() {
        phase = .loading
        loadError = nil
        Task { @MainActor in
            do {
                try await self.generateWorld()
                self.phase = .world
            } catch {
                self.loadError = "We couldn't finish weaving your world. Let's try once more."
                self.phase = .error
            }
        }
    }

    /// Resolve the world for the current answers, bounded by `generationTimeout`.
    /// The scoring itself is synchronous and instant; the brief sleep is just a
    /// "generating world" beat (v2: this body becomes a real API call). Wrapping
    /// it in a timeout race means a future hang turns into a recoverable error
    /// instead of a stuck loading screen.
    @MainActor
    private func generateWorld() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                // A brief beat so the loading screen registers. Kept short — the
                // scoring below is instant, so a long sleep only adds perceived
                // slowness.
                try await Task.sleep(for: .milliseconds(600))

                // Research direction 6->7: compute the hidden continuous scores
                // first, then map them into world parameters.
                let scores = Scorer.score(self.answers)
                self.axisScores = scores
                self.worldParams = WorldMapper.map(scores)
                // title/blurb are derived from the archetype, keeping the overlay
                // text consistent with the USDZ scene.
                self.world = WorldCatalog.world(for: self.worldParams!.archetype)
            }
            group.addTask {
                try await Task.sleep(for: self.generationTimeout)
                throw WorldGenTimeout()
            }
            // Take whichever finishes first: success cancels the timeout, a
            // timeout cancels (and surfaces over) the in-flight generation.
            try await group.next()
            group.cancelAll()
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
        loadError = nil
        phase = .splash
    }
}

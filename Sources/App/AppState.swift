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

    /// AI-generated Hero's-Journey series (current self → ideal self) shown in the art
    /// gallery's wall frames. When non-empty, the gallery uses these instead of the bundled
    /// beach placeholders. Set by `GeneratingScreen` before the user enters the gallery.
    var galleryImages: [UIImage] = []

    /// Future Museum run: the Curator's 5-beat story and the answers it was built from.
    /// Set by `GeneratingScreen` alongside `galleryImages`; consumed by the in-gallery voice
    /// (per-beat narration + push-to-talk) and the closing decision moment.
    var museumStory: MuseumStory?
    var museumAnswers: MuseumAnswers?

    /// The single Curator voice for an open museum gallery — shared by the floating voice orb
    /// (push-to-talk) and the in-gallery proximity narrator, so both use one audio session and
    /// never talk over each other. Created on entering the gallery; cleared on exit.
    var museumConversation: ConversationService?

    /// Hidden continuous scores (the bottom layer of research direction 6) and the world
    /// parameters they map to (direction 7). Computed and stored from Phase 3 on; the
    /// display layer consumes `worldParams` from Phase 2 on.
    var axisScores: AxisScores?
    var worldParams: WorldParams?

    /// DEV (visionOS): which dev-menu feature is presented. Hoisted out of the dev-menu
    /// window's local `@State` so the Oops splat world can dismiss + reopen that window
    /// (clearing the floating panel during full immersion) without losing the user's
    /// place. `DevMenuView` binds its `fullScreenCover` to this.
    var devActiveFeature: DevFeature?

    /// One-shot: when set, `OopsFlowView` jumps to this screen on appear. Used to land on
    /// `.reflection` after the user leaves the immersive splat world (the dev-menu window
    /// is recreated on the way back, so the screen can't live in the view's `@State`).
    var oopsResumeScreen: OopsScreen?

    /// Quiz done -> loading -> resolve the world -> enter the world.
    func finishQuiz() {
        phase = .loading
        Task {
            // A brief "generating world" beat so the loading screen registers
            // (v2: this becomes a real API call). Kept short — the scoring below
            // is instant, so a long sleep only adds perceived slowness.
            try? await Task.sleep(for: .milliseconds(600))
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

    /// Populate a neutral default world (scores/params/world) WITHOUT touching `phase`.
    /// Used by the Oops flow, which renders `WorldView` directly rather than via the
    /// `phase`-driven `RootView`.
    func loadDefaultWorld() {
        let scores = AxisScores.neutral
        axisScores = scores
        let params = WorldMapper.map(scores)
        worldParams = params
        world = WorldCatalog.world(for: params.archetype)
    }

    /// Loads the Richards Art Gallery USDZ as the Oops flow world. No narration/title
    /// world object is needed — the Oops flow has its own copy. Social density = 0 keeps
    /// companion orbs out of the gallery. Light params are neutral so the USDZ's own
    /// baked lighting reads correctly without a heavy additive directional overlay.
    func loadGalleryWorld() {
        worldParams = WorldParams(
            archetype: .artGallery,
            lightIntensity: 300,
            colorTemperature: 5500,
            saturation: 1.0,
            socialDensity: 0,
            openness: 0.5,
            biophilicDensity: 0.5,
            focal: .ownPath
        )
        world = nil
    }

    /// DEV ONLY — preload a neutral default world so the dev menu's "World" option
    /// can jump straight into `WorldView`, skipping the quiz.
    func loadDefaultWorldForTesting() {
        loadDefaultWorld()
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
        galleryImages = []
        museumStory = nil
        museumAnswers = nil
        museumConversation = nil
        phase = .splash
    }
}

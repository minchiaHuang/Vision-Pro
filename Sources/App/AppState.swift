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

/// User-tunable settings for an open museum gallery, surfaced in the in-world "⋯" settings
/// popover. Lives on `AppState` so the floating control window, the immersive view (music +
/// locomotion), and the per-frame plaques all read one source of truth.
@Observable
final class MuseumSettings {
    /// Spoken exhibit narration (the per-frame play buttons). Off hides those buttons.
    var audioGuideOn = true
    /// Looping background music (`MuseumMusicPlayer`).
    var musicOn = true
    /// Show the on-screen forward/turn pad in the control bar (default off — gamepad is primary).
    var showMovePad = false
    /// Global walk-speed multiplier — scales all locomotion (gamepad + on-screen pad). 0.5–1.5,
    /// 1.0 = unscaled.
    var moveSpeed: Float = 1.0
    /// Eye-height offset in metres, added on top of the world's default standing height (BA396:
    /// the portrait-frame height). Lets the visitor raise/lower their viewpoint live.
    var eyeHeight: Float = 0
    /// Show the Curator's spoken line as text on the exhibit being described.
    var subtitlesOn = false
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

    /// The Future Museum pipeline. Owned here (not by `GeneratingScreen`) so Stage B image
    /// painting keeps running after the user enters the museum — entering tears down the
    /// dev-menu window and `GeneratingScreen` with it. The immersive gallery observes this
    /// generator's `nodes` and re-textures each wall as its painting lands.
    var museumGenerator = MuseumGenerator()

    /// The single Curator voice for an open museum gallery — shared by the floating voice orb
    /// (push-to-talk) and the in-gallery proximity narrator, so both use one audio session and
    /// never talk over each other. Created on entering the gallery; cleared on exit.
    var museumConversation: ConversationService?

    /// In-world settings for the open museum gallery (audio guide, music, move pad, speed).
    var museumSettings = MuseumSettings()

    /// True while the `world` ImmersiveSpace is presented. Set by `ImmersiveWorldView` on
    /// appear/disappear; the Oops gallery control window observes the true→false transition to
    /// tear itself down on EVERY exit path (button, gamepad, Digital Crown, system close).
    var immersiveWorldOpen = false

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

    /// DEV ONLY — loads the BA396 exhibition-hall USDZ as a standalone world for the
    /// dev-menu BA396 entry. Mirrors `loadGalleryWorld()`: social density = 0, neutral
    /// light params so the model's own baked materials read correctly. BA396 uses its
    /// own archetype, so the `.artGallery`-only branches in `ParametricWorldBuilder`
    /// (photo-frame swap, 0.7 scale, interior-bounds exclusion) do not fire — the model
    /// shows as authored.
    func loadBA396World() {
        worldParams = WorldParams(
            archetype: .ba396Museum,
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
        // `MuseumGenerator` is `@MainActor`; hop on (this nonisolated `restart()` is only ever
        // called from MainActor UI, but the call must be expressed on the actor). Cancels any
        // in-flight Stage B paint task so a stale run can't keep painting after a restart.
        Task { @MainActor in museumGenerator.reset() }
        museumConversation = nil
        loadError = nil
        phase = .splash
    }
}

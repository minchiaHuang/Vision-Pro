import SwiftUI

/// The screens of the Oops prototype flow (mirrors the React `screen` state). After the
/// user steps out of the 3D world they land on the `reflection` screen (5 questions).
enum OopsScreen {
    case home, safety, privacy, quiz, generating, world, reflection, library
}

/// Held-in-memory answers for the quiz (front-end only — never scored or stored in this
/// pass). The post-world reflection is a passive montage with no input, so it stores nothing.
/// - `quiz`: pill questions — maps question id → selected option index
/// - `quizText`: free-text questions — maps question id → typed string
struct OopsAnswers {
    var quiz: [String: Int] = [:]
    var quizText: [String: String] = [:]
    /// Q3 answer — "What's your ideal future like? Who do you want to become?" — drives the
    /// Hero's Journey image generation goal string.
    var goal: String { quizText["q3"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

/// Self-contained coordinator for the Oops glass flow. Owns its own screen + answer
/// state so it doesn't touch the warm `AppState.phase` machine; it only asks `AppState`
/// to prepare a neutral default world right before entering the existing 3D `WorldView`.
struct OopsFlowView: View {
    @Environment(AppState.self) private var appState
    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    @State private var screen: OopsScreen = .home
    @State private var answers = OopsAnswers()
    @State private var safety = [false, false, false]
    @State private var privacy = [false, false, false]

    /// Looping home ambience. Owned here (not by `HomeScreen`) so it survives the Home → safety
    /// transition: it keeps playing into the safety page and slowly fades out there.
    @State private var ambience = IntroAmbiencePlayer(resource: "home_ambient", volume: 0.48)
    /// How long the ambient bed takes to settle to silence once the safety page appears.
    private let ambienceFadeOut: TimeInterval = 6

    /// Bumped every time we navigate to `.home`, then used as HomeScreen's `.id`. Landing on
    /// home from a different screen (e.g. returning from the reflection montage) reuses the
    /// same `switch` branch, so SwiftUI keeps the old HomeScreen + its `@State` alive and the
    /// `onAppear`-driven opening (floating frames → 3s hold → logo/buttons reveal) never
    /// replays. Giving it a fresh identity forces a clean re-mount, so every arrival on home
    /// plays the exact same entrance as the first launch.
    @State private var homeAppearance = 0

    private func go(_ s: OopsScreen) {
        if s == .home { homeAppearance += 1 }
        withAnimation(.easeInOut(duration: 0.5)) { screen = s }
    }

    var body: some View {
        ZStack {
            if screen == .world {
                // Entering the 3D world: never zoomed — it's immersive content.
                OopsWorldContainer(onExit: { go(.reflection) })
            } else {
                // All onboarding/quiz/preview screens are pinch-zoomable on Vision Pro.
                ZoomableContent {
                    screenView(screen)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            // Returning from the gallery world recreates this window; resume at
            // the requested screen (reflection) rather than restarting at .home.
            if let resume = appState.oopsResumeScreen {
                screen = resume
                appState.oopsResumeScreen = nil
                #if os(visionOS)
                // The world's control + voice windows can't reliably dismiss themselves (visionOS
                // single-`Window` limitation: dismissWindow(self) and `\.dismiss` both fail). Close
                // them from here — the dev-menu window reopening on return — where `dismissWindow(id:)`
                // targets OTHER windows and IS reliable. No-op if a window is already gone.
                for id in ["oops-gallery-controls", "museum-voice-orb",
                           "oops-world-controls", "oops-voice-orb"] {
                    dismissWindow(id: id)
                }
                #endif
            }
            if screen == .home { ambience.start() }
        }
        // Drive the home ambience across screens: play on Home, carry into the safety page and
        // fade out there, and ensure it's stopped on any other destination.
        .onChange(of: screen) { _, newScreen in
            switch newScreen {
            case .home:   ambience.start()
            case .safety: ambience.fadeOut(over: ambienceFadeOut)
            default:      ambience.stop()
            }
        }
        #if os(visionOS)
        // Let the cover background go clear so the transparent `OopsPassthrough`
        // reveals the window glass / real room rather than an opaque default backing.
        .presentationBackground(.clear)
        #endif
    }

    /// The current non-world screen. `.world` is handled separately (outside the zoom
    /// wrapper), so it returns an empty view here.
    @ViewBuilder
    private func screenView(_ screen: OopsScreen) -> some View {
        switch screen {
        case .home:
            // `.id` keyed to the visit count so each arrival re-mounts HomeScreen and replays
            // its opening animation (see `homeAppearance`).
            HomeScreen(onGenerate: { go(.safety) }, onVisitOld: { go(.library) })
                .id(homeAppearance)
        case .safety:
            DeclarationScreen(
                label: "03 Safety Declaration", title: "Safety Declaration",
                subtitle: OopsContent.declarationIntro,
                items: OopsContent.safety, cta: "I agree & continue",
                checks: $safety, onCta: { go(.privacy) }, onBack: { go(.home) })
        case .privacy:
            DeclarationScreen(
                label: "04 Privacy Preferences", title: "Privacy Preferences",
                subtitle: OopsContent.privacyIntro,
                items: OopsContent.privacy, cta: "Start",
                checks: $privacy, requireAll: false, onCta: { go(.quiz) }, onBack: { go(.safety) })
        case .quiz:
            QuizScreen(answers: $answers, onFinish: { go(.generating) }, onBack: { go(.home) })
        case .generating:
            // The finished quiz answers now drive the Curator pipeline (story + 5 images)
            // inside GeneratingScreen; the result is stored on AppState before enterWorld().
            GeneratingScreen(answers: answers) { enterWorld() }
        case .world:
            EmptyView()
        case .reflection:
            // A passive question montage over the world; when it ends, return Home.
            ReflectionFlowView(onFinish: { go(.home) })
        case .library:
            // Game-save-style grid of past visits. Tapping one restores it onto AppState and
            // re-enters the museum through the very same `enterWorld()` path as a fresh run —
            // but with no generation, so no AI is re-run.
            OopsLibraryScreen(
                onSelect: { record in
                    appState.loadSavedVisit(record)
                    enterWorld()
                },
                onBack: { go(.home) })
        }
    }

    /// Enters the BA396 exhibition hall (the Oops-flow museum world).
    /// - visionOS: sets worldParams to the BA396 archetype, opens the shared RealityKit
    ///   `world` ImmersiveSpace (head tracking + gamepad locomotion), and shows the small
    ///   `oops-gallery-controls` floating panel. Leaving that panel reopens the dev-menu
    ///   at the reflection screen. The generated beat images on `appState.galleryImages`
    ///   are composited onto BA396's 6 portrait walls by `ParametricWorldBuilder`.
    /// - iPad: loads BA396 worldParams and shows the in-cover `WorldView` (ParametricWorldView).
    private func enterWorld() {
        // Stand up the one shared Curator voice. The real flow grounds it in the generated story;
        // "Visit Old World" (no story) grounds it in the sample beats so the wall-plaque play
        // button (`describeExhibit`) and the push-to-talk orb are still testable there.
        let convo = ConversationService()
        let story = appState.museumStory ?? BeatPlaqueSample.story
        convo.configureCurator(story: story, answers: appState.museumAnswers ?? MuseumAnswers())
        appState.museumConversation = convo
        #if os(visionOS)
        Task {
            appState.loadBA396World()
            if case .opened = await openImmersiveSpace(id: "world") {
                openWindow(id: "oops-gallery-controls")
                // The gallery opens silent: the Curator voice orb is no longer auto-shown.
                // It's opened on demand from the settings popover's "Talk to the guide" row
                // (`museumConversation` is still configured above so the frame play buttons work).
                dismissWindow(id: "dev-menu")
            }
        }
        #else
        appState.loadBA396World()
        go(.world)
        #endif
    }
}

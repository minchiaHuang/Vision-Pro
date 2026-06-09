import SwiftUI

/// The screens of the Oops prototype flow (mirrors the React `screen` state). After the
/// user steps out of the 3D world they land on the `reflection` screen (5 questions).
enum OopsScreen {
    case opening, home, safety, privacy, quiz, generating, world, reflection
}

/// Held-in-memory answers for the quiz + post-world reflection (front-end only — never
/// scored or stored in this pass).
/// - `quiz`: pill questions — maps question id → selected option index
/// - `quizText`: free-text questions — maps question id → typed string
/// - `r1`–`r5`: reflection free-text answers (post-world)
struct OopsAnswers {
    var quiz: [String: Int] = [:]
    var quizText: [String: String] = [:]
    /// Q3 answer — "What's your ideal future like? Who do you want to become?" — drives the
    /// Hero's Journey image generation goal string.
    var goal: String { quizText["q3"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var r1 = ""
    var r2 = ""
    var r3 = ""
    var r4 = ""
    var r5 = ""
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

    @State private var screen: OopsScreen = .opening
    @State private var answers = OopsAnswers()
    @State private var safety = [false, false, false]
    @State private var privacy = [false, false, false]

    private func go(_ s: OopsScreen) {
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
            // the requested screen (reflection) rather than restarting at .opening.
            if let resume = appState.oopsResumeScreen {
                screen = resume
                appState.oopsResumeScreen = nil
            }
        }
        // The voice orb is a separate window; fold the speech it recognizes into the flow's
        // answers so dictation and typing share one set of answers (dictation replaces the field).
        .onChange(of: appState.quizVoice.text) { _, dict in
            for (id, value) in dict { answers.quizText[id] = value }
        }
        #if os(visionOS)
        // Show the floating speech-to-text orb only while on the Quiz screen.
        .onChange(of: screen) { _, s in
            if s == .quiz {
                openWindow(id: "quiz-voice-orb")
            } else {
                dismissWindow(id: "quiz-voice-orb")
                appState.quizVoice.activeQuestionID = nil
            }
        }
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
        case .opening:
            OpeningScreen { go(.home) }
        case .home:
            HomeScreen(onGenerate: { go(.safety) }, onVisitOld: { enterWorld() })
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
            ReflectionFlowView(answers: $answers, onFinish: { go(.home) })
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
        // When a Curator story exists (the museum flow, not "visit old world"), stand up the one
        // shared voice now so both the orb and the in-gallery proximity narrator use it.
        if let story = appState.museumStory {
            let convo = ConversationService()
            convo.configureCurator(story: story, answers: appState.museumAnswers ?? MuseumAnswers())
            appState.museumConversation = convo
        }
        #if os(visionOS)
        Task {
            appState.loadBA396World()
            if case .opened = await openImmersiveSpace(id: "world") {
                openWindow(id: "oops-gallery-controls")
                if appState.museumConversation != nil { openWindow(id: "museum-voice-orb") }
                dismissWindow(id: "dev-menu")
            }
        }
        #else
        appState.loadBA396World()
        go(.world)
        #endif
    }
}

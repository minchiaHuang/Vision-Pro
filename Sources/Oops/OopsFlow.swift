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
            // Q2 free-text answer drives the Hero's Journey prompt; fall back to a generic goal
            // if the user somehow skipped it (should not happen — Next is disabled when empty).
            let goal = answers.goal.isEmpty ? "build a meaningful future" : answers.goal
            GeneratingScreen(goal: goal) { enterWorld() }
        case .world:
            EmptyView()
        case .reflection:
            ReflectionFlowView(answers: $answers, onFinish: { go(.home) })
        }
    }

    /// Enters the Richards Art Gallery.
    /// - visionOS: sets worldParams to the gallery archetype, opens the shared RealityKit
    ///   `world` ImmersiveSpace (head tracking + gamepad locomotion), and shows the small
    ///   `oops-gallery-controls` floating panel. Leaving that panel reopens the dev-menu
    ///   at the reflection screen.
    /// - iPad: loads gallery worldParams and shows the in-cover `WorldView` (ParametricWorldView).
    private func enterWorld() {
        #if os(visionOS)
        Task {
            appState.loadGalleryWorld()
            if case .opened = await openImmersiveSpace(id: "world") {
                openWindow(id: "oops-gallery-controls")
                dismissWindow(id: "dev-menu")
            }
        }
        #else
        appState.loadGalleryWorld()
        go(.world)
        #endif
    }
}

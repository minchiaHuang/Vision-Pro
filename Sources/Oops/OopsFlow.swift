import SwiftUI

/// The screens of the Oops prototype flow (mirrors the React `screen` state). After the
/// user steps out of the 3D world they land on the `reflection` screen (5 questions).
enum OopsScreen {
    case opening, home, safety, privacy, quiz, generating, preview, world, reflection
}

/// Held-in-memory answers for the quiz + post-world reflection (front-end only — never
/// scored or stored in this pass). String for text/area questions, Int 0...10 for the
/// single slider; `r1`–`r5` hold the reflection free-text answers.
struct OopsAnswers {
    var q1 = "To find my passion"
    var q3 = ""
    var q4 = ""
    var q5 = ""
    var q6 = ""
    var q2 = 6   // slider
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

    private func restart() {
        answers = OopsAnswers()
        safety = [false, false, false]
        privacy = [false, false, false]
        withAnimation(.easeInOut(duration: 0.5)) { screen = .opening }
    }

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

                // Restart pill — bottom-left chrome, kept outside the zoom so it stays
                // a fixed size (matches the prototype chrome).
                VStack {
                    Spacer()
                    HStack {
                        Button(action: restart) {
                            Label("Restart", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            // Returning from the immersive splat world recreates this window; resume at
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
                items: OopsContent.safety, cta: "I agree & continue",
                checks: $safety, onCta: { go(.privacy) })
        case .privacy:
            DeclarationScreen(
                label: "04 Privacy Preferences", title: "Privacy Preferences",
                items: OopsContent.privacy, cta: "Start",
                checks: $privacy, onCta: { go(.quiz) })
        case .quiz:
            QuizScreen(answers: $answers, onFinish: { go(.generating) }, onBack: { go(.home) })
        case .generating:
            GeneratingScreen { go(.preview) }
        case .preview:
            PreviewScreen(onEnter: { enterWorld() }, onRetry: { go(.quiz) })
        case .world:
            EmptyView()
        case .reflection:
            ReflectionFlowView(answers: $answers, onFinish: { go(.home) })
        }
    }

    /// Enters the walkable 3D world.
    /// - visionOS: opens the 6DoF Gaussian-splat immersive space directly (bundled
    ///   "Vibrant Loft Art Studio"), then swaps the dev-menu window for the small
    ///   `oops-world-controls` window so full immersion isn't cluttered by a floating
    ///   panel. Leaving that window reopens the dev-menu at the reflection screen.
    /// - iPad: prepares a neutral default world and shows the in-cover `WorldView`.
    private func enterWorld() {
        #if os(visionOS)
        Task {
            guard let url = Bundle.main.url(forResource: "vibrant_loft_art_studio",
                                            withExtension: "spz") else { return }
            SplatManualInput.shared.reset()
            if case .opened = await openImmersiveSpace(id: "splat",
                                                       value: SplatEntry(url: url, flipUpsideDown: true)) {
                openWindow(id: "oops-world-controls")
                dismissWindow(id: "dev-menu")
            }
        }
        #else
        appState.loadDefaultWorld()
        go(.world)
        #endif
    }
}

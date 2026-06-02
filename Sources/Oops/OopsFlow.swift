import SwiftUI

/// The nine screens of the Oops prototype flow (mirrors the React `screen` state).
enum OopsScreen {
    case opening, home, safety, privacy, quiz, generating, preview, world, exit
}

/// Held-in-memory answers for the 6 reflective questions (front-end only — never scored
/// in this pass). String for text/area questions, Int 0...10 for the single slider.
struct OopsAnswers {
    var q1 = "To find my passion"
    var q3 = ""
    var q4 = ""
    var q5 = ""
    var q6 = ""
    var q2 = 6   // slider
}

/// Self-contained coordinator for the Oops glass flow. Owns its own screen + answer
/// state so it doesn't touch the warm `AppState.phase` machine; it only asks `AppState`
/// to prepare a neutral default world right before entering the existing 3D `WorldView`.
struct OopsFlowView: View {
    @Environment(AppState.self) private var appState

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
                OopsWorldContainer(onExit: { go(.exit) })
            case .exit:
                ExitScreen(onReenter: { enterWorld() }, onHome: { go(.home) })
            }

            // Restart pill — bottom-left of the viewport (matches the prototype chrome).
            if screen != .world {
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
    }

    /// Prepares a neutral default world (no scoring this pass) and shows the existing 3D world.
    private func enterWorld() {
        appState.loadDefaultWorld()
        go(.world)
    }
}

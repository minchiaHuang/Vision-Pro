import SwiftUI

/// Self-contained coordinator for the Future Museum feature. Two screens — the question
/// form and the generated gallery — with its own state. Presented full-screen by
/// `DevFeatureContainer`, which already supplies the floating back-to-menu button, so this
/// view adds no chrome of its own.
struct MuseumFlowView: View {
    private enum Screen { case questions, gallery }

    @State private var screen: Screen = .questions
    @State private var answers = MuseumAnswers()
    @State private var generator = MuseumGenerator()

    var body: some View {
        ZStack {
            switch screen {
            case .questions:
                MuseumQuestionsView(answers: $answers) {
                    withAnimation(.easeInOut(duration: 0.35)) { screen = .gallery }
                }
            case .gallery:
                MuseumGalleryView(generator: generator,
                                  onRestart: restart)
                    .task { await generator.run(answers) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func restart() {
        generator.reset()
        withAnimation(.easeInOut(duration: 0.35)) { screen = .questions }
    }
}

#Preview("MuseumFlow") {
    MuseumFlowView()
}

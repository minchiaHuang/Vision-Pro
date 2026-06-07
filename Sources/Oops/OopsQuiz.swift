import SwiftUI

/// 05 · Quiz — a scrollable glass window of 4 single-select questions, a back button that
/// raises the "Are you sure?" dialog, and a Finish CTA. Answers are front-end only.
struct QuizScreen: View {
    @Binding var answers: OopsAnswers
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var confirm = false

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)

            // A capped, centred glass card with the questions scrolling inside it. The
            // height is bounded to a fraction of the window (so it always leaves a margin
            // and stays inside the viewport on Vision Pro, where the window can be taller
            // than the comfortable view) and clamped to an absolute max. The inner
            // ScrollView then has a definite height, so content scrolls within the card
            // instead of the card growing past the screen and clipping the lower questions.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: 56) {
                            ForEach(Array(OopsContent.questions.enumerated()), id: \.element.id) { index, q in
                                questionView(number: index + 1, q)
                            }
                            HStack {
                                Spacer()
                                Button("Finish", action: onFinish).buttonStyle(OopsButton())
                                Spacer()
                            }
                            .padding(.top, 6)
                        }
                        .padding(.horizontal, 80)
                        .padding(.top, 24)
                        .padding(.bottom, 60)
                    }
                }
                .frame(width: min(1100, geo.size.width * 0.86),
                       height: min(760, geo.size.height * 0.8))
                .oopsWindow()
                .frame(maxWidth: .infinity, maxHeight: .infinity) // centre within the window
            }

            if confirm {
                OopsDialog(
                    title: "Are you sure?",
                    message: "Your progress will be lost forever and you will need to re-enter all answers if you re-enter.",
                    confirmTitle: "Yes",
                    onConfirm: { confirm = false; onBack() },
                    onCancel: { confirm = false })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: confirm)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quiz").oopsTitle(34)
                Text("Take a few minutes to answer these questions. Your answers will shape the world that's built for you")
                    .oopsSub(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 80)
            .padding(.trailing, 70)
            .padding(.top, 56)

            Button { confirm = true } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .padding(.top, 44)
        }
    }

    /// One numbered question with its four single-select options laid out 2×2.
    @ViewBuilder
    private func questionView(number: Int, _ q: OopsContent.Question) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("\(number). \(q.label)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 24),
                          GridItem(.flexible(), spacing: 24)],
                spacing: 18
            ) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { idx, option in
                    optionButton(option, selected: answers.quiz[q.id] == idx) {
                        answers.quiz[q.id] = idx
                    }
                }
            }
        }
    }

    /// A frosted glass pill option. Selected = brighter fill and a full white ring.
    private func optionButton(_ text: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 60)
                .padding(.horizontal, 22)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(selected ? 0.30 : 0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(.white.opacity(selected ? 0.95 : 0.32),
                                           lineWidth: selected ? 2.5 : 1.5))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

// MARK: - Previews

#Preview("QuizScreen") {
    QuizScreen(answers: .constant(OopsAnswers()), onFinish: {}, onBack: {})
        .preferredColorScheme(.dark)
}

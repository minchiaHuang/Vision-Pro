import SwiftUI

/// 05 · Quiz — 6 questions, one per screen, paginated (Figma "Quiz Iterations").
///
/// Screen layout:
///   • Q1 only: glass card with "Quiz" bold title + subtitle, then question + horizontal pills
///   • Q2–Q6: glass card with just the question label + free-text textarea
///   • All screens: circular glass back button (top-left), "Next >" text (bottom-right)
///   • Q6 (last): "Generate my world" pill CTA instead of "Next >"
///
/// Back on Q1 raises the "Are you sure?" exit dialog.
/// Back on Q2–Q6 navigates to the previous question.
/// "Next >" is disabled until the current question has an answer.
struct QuizScreen: View {
    @Binding var answers: OopsAnswers
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var currentIndex = 0
    @State private var confirm = false

    private var questions: [OopsContent.Question] { OopsContent.questions }
    private var current: OopsContent.Question { questions[currentIndex] }
    private var isFirst: Bool { currentIndex == 0 }
    private var isLast:  Bool { currentIndex == questions.count - 1 }

    private var canAdvance: Bool {
        if current.isTextInput {
            let txt = answers.quizText[current.id] ?? ""
            return !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return answers.quiz[current.id] != nil
        }
    }

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)

            VStack(spacing: 0) {
                // Q1: full header (title + subtitle + back button)
                // Q2–Q6: compact header (back button only)
                if isFirst {
                    fullHeader
                } else {
                    compactHeader
                }

                Spacer(minLength: 0)

                questionContent
                    .padding(.horizontal, 72)
                    .animation(.easeInOut(duration: 0.28), value: currentIndex)

                Spacer(minLength: 0)

                navigationRow
                    .padding(.horizontal, 72)
                    .padding(.bottom, 36)
            }
            .frame(width: 920, height: 530)
            .oopsWindow()

            if confirm {
                OopsDialog(
                    title: "Are you sure?",
                    message: "Your progress will be lost and you will need to re-enter all answers.",
                    confirmTitle: "Yes",
                    onConfirm: { confirm = false; onBack() },
                    onCancel:  { confirm = false })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: confirm)
    }

    // MARK: - Headers

    /// Q1: "Quiz" title + subtitle, with back button in the top-left corner.
    private var fullHeader: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quiz")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                Text("Take a few minutes to answer these questions. Your answers will shape the world that's built for you")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 108)
            .padding(.trailing, 56)
            .padding(.top, 44)

            backButton
                .padding(.leading, 28)
                .padding(.top, 40)
        }
    }

    /// Q2–Q6: back button only, no title text.
    private var compactHeader: some View {
        HStack {
            backButton
            Spacer()
        }
        .padding(.leading, 28)
        .padding(.top, 40)
        .padding(.bottom, 8)
    }

    private var backButton: some View {
        Button {
            if isFirst {
                confirm = true
            } else {
                withAnimation(.easeInOut(duration: 0.28)) { currentIndex -= 1 }
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.20), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question content

    @ViewBuilder
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Qn \(currentIndex + 1): \(current.label)")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if current.isTextInput {
                freeTextArea
            } else {
                pillRow
            }
        }
        .id(currentIndex)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Pill row (Q1 — 4 options in a horizontal row)

    private var pillRow: some View {
        HStack(spacing: 18) {
            ForEach(Array(current.options.enumerated()), id: \.offset) { idx, option in
                pillButton(option, selected: answers.quiz[current.id] == idx) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        answers.quiz[current.id] = idx
                    }
                }
            }
        }
    }

    private func pillButton(_ text: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .padding(.horizontal, 12)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.37), Color(white: 0.45, opacity: 0.42)],
                        startPoint: UnitPoint(x: 0.08, y: 0.04),
                        endPoint:   UnitPoint(x: 0.95, y: 0.95)
                    )
                )
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        .white.opacity(selected ? 1.0 : 0.8),
                        lineWidth: selected ? 3.0 : 2.3
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 1)
                .scaleEffect(selected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    // MARK: - Free-text area (Q2–Q6)
    // Dark rounded rect, per-question placeholder text from OopsContent.

    private var freeTextArea: some View {
        let binding = Binding<String>(
            get: { answers.quizText[current.id] ?? "" },
            set: { answers.quizText[current.id] = $0 }
        )
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.22))

            if (answers.quizText[current.id] ?? "").isEmpty {
                Text(current.placeholder)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }

            TextField("", text: binding, axis: .vertical)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(5...7)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(height: 180)
    }

    // MARK: - Navigation row

    @ViewBuilder
    private var navigationRow: some View {
        if isLast {
            HStack {
                Spacer()
                Button("Generate my world", action: onFinish)
                    .buttonStyle(OopsButton())
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.38)
                Spacer()
            }
        } else {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { currentIndex += 1 }
                } label: {
                    Text("Next >")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(canAdvance ? .white : .white.opacity(0.28))
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            }
        }
    }
}

// MARK: - Preview

#Preview("QuizScreen") {
    QuizScreen(answers: .constant(OopsAnswers()), onFinish: {}, onBack: {})
        .preferredColorScheme(.dark)
}

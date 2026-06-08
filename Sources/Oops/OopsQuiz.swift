import SwiftUI

/// 05 · Quiz — one question per screen, paginated.
///
/// Layout (matching Figma "quiz variations"):
///   - Glass card (oopsWindow), fixed 920×530
///   - Top-left: circular glass back button (chevron ‹)
///   - Header: "Quiz" bold + subtitle
///   - Centre: question label + pill row (Q1) or free-text area (Q2–Q4)
///   - Bottom-right: "Next ›" text (disabled until answered)
///   - Bottom-centre on last question: "Generate my world" pill CTA
///
/// Back on the first question raises the existing "Are you sure?" exit dialog.
/// Back on subsequent questions navigates to the previous question.
struct QuizScreen: View {
    @Binding var answers: OopsAnswers
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var currentIndex = 0
    @State private var confirm = false

    private var questions: [OopsContent.Question] { OopsContent.questions }
    private var current: OopsContent.Question { questions[currentIndex] }
    private var isFirst: Bool { currentIndex == 0 }
    private var isLast: Bool { currentIndex == questions.count - 1 }

    /// "Next ›" / "Generate my world" is only active when the current question has an answer.
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
                header
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
                    onCancel: { confirm = false })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: confirm)
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quiz")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                Text("Take a few minutes to answer these questions. Your answers will shape the world that's built for you")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 108)   // clear of the back button
            .padding(.trailing, 56)
            .padding(.top, 44)

            // Circular glass back button (Figma: 60×60, backdrop blur, white/20)
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
            .padding(.leading, 28)
            .padding(.top, 40)
        }
    }

    // MARK: - Question content

    @ViewBuilder
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // "Qn N: question text"
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
        .id(currentIndex)   // forces SwiftUI to re-create (and animate) on page change
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Pill row (Q1 — horizontal 4-up)

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
                // Figma: glass gradient fill + white border
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

    // MARK: - Free-text area (Q2–Q4)
    // Figma: dark rounded rect (rgba 0,0,0,0.2), radius 21, placeholder at 15% white opacity.

    private var freeTextArea: some View {
        let binding = Binding<String>(
            get: { answers.quizText[current.id] ?? "" },
            set: { answers.quizText[current.id] = $0 }
        )
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.22))

            if (answers.quizText[current.id] ?? "").isEmpty {
                Text("Share as much detail as you can. The more context you give, the better the outcome")
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
        .frame(height: 160)
    }

    // MARK: - Navigation row

    @ViewBuilder
    private var navigationRow: some View {
        if isLast {
            // Final question: centred "Generate my world" pill
            HStack {
                Spacer()
                Button("Generate my world", action: onFinish)
                    .buttonStyle(OopsButton())
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.38)
                Spacer()
            }
        } else {
            // Intermediate questions: "Next ›" text at trailing edge
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

import SwiftUI

/// 05 · Quiz — 6 questions, one per screen, paginated (Figma "Quiz Iterations").
///
/// Screen layout:
///   • Q1 only: glass card with "Quiz" bold title + subtitle, then question + horizontal pills
///   • Q2–Q6: glass card with just the question label + free-text textarea
///   • All screens: circular glass back button (top-left), "Next >" text (bottom-right)
///   • Q6 (last): "Generate my world" pill CTA (bottom-centre) instead of "Next >"
///
/// Dimensions are proportional to the Figma "Quiz Iterations" card (1392×807 px) at ×0.66
/// scale to fit the fixed 920×530 pt card used across all Oops screens.
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

            // Glass card — ZStack so back button and nav can be placed independently
            // of the content column.
            ZStack(alignment: .topLeading) {

                // ── Content column (vertically centred via Spacers) ──────────────────
                VStack(spacing: 0) {
                    if isFirst {
                        // Q1: "Quiz" title + subtitle, indented to clear the back button.
                        quizHeader
                    } else {
                        // Q2–Q6: empty space matching back-button row height.
                        Color.clear.frame(height: 76)   // 32pt top pad + 44pt button
                    }
                    Spacer(minLength: 0)
                    questionContent
                        .padding(.horizontal, 80)
                        .animation(.easeInOut(duration: 0.28), value: currentIndex)
                    Spacer(minLength: 0)
                    // Reserve space at the bottom so content doesn't slide under the nav.
                    Color.clear.frame(height: 70)
                }
                .frame(width: 920, height: 530)

                // ── Back button — Figma: left-39, top-49 in 1392×807 → 26/32 at ×0.66 ──
                backButton
                    .padding(.leading, 26)
                    .padding(.top, 32)

                // ── Navigation — pinned to card bottom ──────────────────────────────────
                VStack {
                    Spacer()
                    navigationRow
                        .padding(.horizontal, 80)
                        .padding(.bottom, 32)
                }
                .frame(width: 920, height: 530)
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

    // MARK: - Q1 Quiz header

    /// "Quiz" bold title + descriptive subtitle — only visible on Q1. Left-indented so it
    /// starts after the back button circle (26pt leading + 44pt circle + 18pt gap = 88pt).
    private var quizHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quiz")
                // Figma: Roboto Bold 36px → 28pt at ×0.66 (proportional to card width)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text("Take a few minutes to answer these questions. Your answers will shape the world that's built for you")
                // Figma: Roboto Regular 25px → 17pt
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 88)
        .padding(.trailing, 56)
        .padding(.top, 32)
    }

    // MARK: - Back button

    /// Figma: 60×60 px circle, rgba(255,255,255,0.2) bg, backdrop-blur 67.955 → 44×44 pt.
    private var backButton: some View {
        Button {
            if isFirst {
                confirm = true
            } else {
                withAnimation(.easeInOut(duration: 0.28)) { currentIndex -= 1 }
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.20), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question content

    @ViewBuilder
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Figma: Roboto Regular 26px → 18pt; same for all 6 screens.
            Text("Qn \(currentIndex + 1): \(current.label)")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if current.isTextInput {
                freeTextArea
            } else {
                // Extra top gap to match Figma gap-[40px] between question and pills.
                pillRow.padding(.top, 14)
            }
        }
        .id(currentIndex)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Pill row (Q1 — 4 options, fixed-width, horizontal)

    private var pillRow: some View {
        HStack(spacing: 20) {
            ForEach(Array(current.options.enumerated()), id: \.offset) { idx, option in
                pillButton(option, selected: answers.quiz[current.id] == idx) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        answers.quiz[current.id] = idx
                    }
                }
            }
        }
    }

    /// Figma pill: 250×75 px → 165×50 pt; Capsule; white border 2.314px → 1.5pt;
    /// gradient linear(167°, white.37 → grey.42); ultraThinMaterial; drop-shadow 18%.
    private func pillButton(_ text: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                // Figma: Roboto Medium 20px → 14pt
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 165, height: 50)
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
                        lineWidth: selected ? 2.5 : 1.5
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 1)
                .scaleEffect(selected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    // MARK: - Free-text area (Q2–Q6)

    /// Figma: h=360px → 238pt; cornerRadius=20.7px → 14pt; bg=rgba(0,0,0,0.20);
    /// px=50px → 32pt; 32px top spacer before placeholder; placeholder opacity=15%.
    private var freeTextArea: some View {
        let binding = Binding<String>(
            get: { answers.quizText[current.id] ?? "" },
            set: { answers.quizText[current.id] = $0 }
        )
        let isEmpty = (answers.quizText[current.id] ?? "").isEmpty

        return ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.20))

            // Placeholder — faint (15% opacity per Figma), preceded by 21pt top spacer
            // that reproduces the 32px cursor-gap Figma adds before the hint text.
            if isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 21)
                    Text(current.placeholder)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.15))
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .allowsHitTesting(false)
            }

            // Actual text field
            TextField("", text: binding, axis: .vertical)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(5...9)
                .padding(.horizontal, 32)
                .padding(.top, 18)
                .padding(.bottom, 16)
        }
        .frame(height: 238)
    }

    // MARK: - Navigation row

    @ViewBuilder
    private var navigationRow: some View {
        if isLast {
            // Q6: "Generate my world" pill — centred (Figma: left-561 centres a 270px
            // button in the 1392px card → horizontally centred at ×0.66 too).
            HStack {
                Spacer()
                Button(action: onFinish) {
                    Text("Generate my world")
                        // Figma: Roboto Medium 25px → 17pt
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 178, height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.white.opacity(0.37), Color(white: 0.45, opacity: 0.42)],
                                startPoint: UnitPoint(x: 0.08, y: 0.05),
                                endPoint:   UnitPoint(x: 0.95, y: 0.95)
                            )
                        )
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.38)
                Spacer()
            }
        } else {
            // Q1–Q5: "Next >" — Figma: Inter Bold 20px → system bold 17pt; trailing-aligned
            // (Figma: left-1209 in 1392px = ~87% from left → natural HStack trailing).
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { currentIndex += 1 }
                } label: {
                    Text("Next >")
                        .font(.system(size: 17, weight: .bold))
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

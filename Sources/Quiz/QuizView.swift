import SwiftUI

/// 4+1 axis quiz: 4 axis screens (3 sliders each) + hope direction + free text.
struct QuizView: View {
    @Environment(AppState.self) private var appState
    @State private var step = 0

    private var isLast: Bool { step == QuizData.stepCount - 1 }

    private var canContinue: Bool {
        step == 4 ? appState.answers.hope != nil : true
    }

    private var title: String {
        if step < 4 { return QuizData.axisTitles[step] }
        if step == 4 { return "A year from now, you'd want to be\na little closer to—" }
        return "If one word or image came to mind,\nwhat would it be?"
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 26) {
            ProgressPips(step: step, total: QuizData.stepCount)

            Text(title)
                .vaLargeThinTitle(size: 24)
                .lineLimit(3)
                .padding(.horizontal)

            Group {
                switch step {
                case 0, 1, 2, 3:
                    AxisSlidersScreen(
                        questions: QuizData.axisGroups[step],
                        sliderBase: step * 3,
                        answers: $appState.answers
                    )
                case 4:
                    IconCardGrid(
                        options: QuizData.hopeOptions,
                        selection: $appState.answers.hope
                    )
                default:
                    FreeTextScreen(text: $appState.answers.hopeFreeText)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .buttonStyle(SecondaryPillButtonStyle())
                }
                Button(isLast ? "Weave my world" : "Continue") {
                    if isLast { appState.finishQuiz() }
                    else { withAnimation { step += 1 } }
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.45)
            }
        }
        .padding()
        .frame(maxWidth: 700)
    }
}

// MARK: - Progress

private struct ProgressPips: View {
    let step: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.accentColor
                          : (i < step ? Color.secondary.opacity(0.65)
                             : Color.secondary.opacity(0.3)))
                    .frame(width: i == step ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.24), value: step)
            }
        }
    }
}

// MARK: - Axis sliders screen (3 this-or-that rows per axis)

private struct AxisSlidersScreen: View {
    let questions: [ThisOrThat]
    let sliderBase: Int
    @Binding var answers: QuizAnswers

    var body: some View {
        VStack(spacing: 28) {
            ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                ThisOrThatRow(
                    question: q,
                    value: $answers.sliders[sliderBase + i]
                )
            }
        }
        .padding(.horizontal)
    }
}

private struct ThisOrThatRow: View {
    let question: ThisOrThat
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 8) {
            Text(question.question)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Text(question.leftLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(width: 88, alignment: .leading)
                Slider(value: $value, in: 0...1)
                    .tint(.accentColor)
                Text(question.rightLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Q14 hope direction (reuses IconCardGrid below)

// MARK: - Q15 free text (optional)

private struct FreeTextScreen: View {
    @Binding var text: String

    var body: some View {
        VStack(spacing: 12) {
            TextField("optional — skip anytime", text: $text, axis: .vertical)
                .font(.body)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .lineLimit(3...5)

            Text("No answer needed — whatever comes to mind, or nothing at all.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

// MARK: - Q14 icon grid (also used by Q14 hope direction)

private struct IconCardGrid: View {
    let options: [ChoiceOption]
    @Binding var selection: String?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(options) { option in
                let isSelected = selection == option.id
                Button {
                    selection = option.id
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: option.symbol ?? "circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        Text(option.label)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(selectionRing(selected: isSelected, radius: 24))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Shared selection ring

private func selectionRing(selected: Bool, radius: CGFloat = 22) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .stroke(selected ? VATheme.amber : .white.opacity(0.18),
                lineWidth: selected ? 2 : 0.5)
        .shadow(color: selected ? VATheme.amber.opacity(0.45) : .clear, radius: 16)
}

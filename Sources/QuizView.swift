import SwiftUI

/// One-question-at-a-time quiz that resolves a world after the final answer.
struct QuizView: View {
    @Environment(AppState.self) private var appState
    @State private var index = 0

    private var question: QuizQuestion { QuizData.questions[index] }
    private var isLast: Bool { index == QuizData.questions.count - 1 }
    private var progressText: String { "\(index + 1) of \(QuizData.questions.count)" }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Text(progressText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(QuizData.questions.indices, id: \.self) { i in
                        Circle()
                            .fill(i <= index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            Text(question.prompt)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal)

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(question.options) { option in
                    Button {
                        select(option)
                    } label: {
                        Text(option.label)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: 640)
    }

    private func select(_ option: QuizOption) {
        appState.answer(question.dimension, tag: option.tag)
        if isLast {
            appState.finishQuiz()
        } else {
            withAnimation { index += 1 }
        }
    }
}

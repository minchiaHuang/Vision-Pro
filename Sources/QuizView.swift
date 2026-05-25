import SwiftUI

/// Quiz：一次顯示一題，答完最後一題 → finishQuiz()。
struct QuizView: View {
    @Environment(AppState.self) private var appState
    @State private var index = 0

    private var question: QuizQuestion { QuizData.questions[index] }
    private var isLast: Bool { index == QuizData.questions.count - 1 }

    var body: some View {
        VStack(spacing: 28) {
            // 進度
            HStack(spacing: 8) {
                ForEach(QuizData.questions.indices, id: \.self) { i in
                    Circle()
                        .fill(i <= index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Text(question.prompt)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // 選項（2 欄）
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(question.options) { option in
                    Button {
                        select(option)
                    } label: {
                        Text(option.label)
                            .font(.body.weight(.medium))
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

import SwiftUI

/// 17–21 · Reflection — a 5-question reflection the user walks through after stepping out
/// of the 3D world. One question per screen with a frosted textarea; the last step's CTA
/// is "Save & Finish". Self-contained sub-coordinator (mirrors `OopsFlowView`'s style):
/// it owns the current step and writes free-text answers back into the shared
/// `OopsAnswers` (front-end only — never scored or stored in this pass).
struct ReflectionFlowView: View {
    @Binding var answers: OopsAnswers
    let onFinish: () -> Void

    @State private var step = 0

    private var questions: [String] { OopsContent.reflectionQuestions }
    private var isLast: Bool { step == questions.count - 1 }

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)

            VStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 24) {
                    Text(OopsContent.reflectionEyebrow)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(OopsGlass.label2)

                    Text(questions[step])
                        .oopsTitle(30)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(step)                       // crossfade between questions
                        .transition(.opacity)

                    OopsField(text: bindingFor(step),
                              placeholder: OopsContent.reflectionPlaceholder,
                              multiline: true)
                }
                .padding(.vertical, 46)
                .padding(.horizontal, 56)
                .frame(maxWidth: 900)
                .oopsCard()

                HStack(spacing: 22) {
                    if step > 0 {
                        Button("Back", action: back)
                            .buttonStyle(OopsButton(ghost: true, minWidth: 160))
                    }
                    Button(isLast ? "Save & Finish" : "Next", action: next)
                        .buttonStyle(OopsButton(minWidth: isLast ? 280 : 200))
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)

            VStack {
                Spacer()
                ReflectionDots(total: questions.count, current: step)
                    .padding(.bottom, 18)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: step)
    }

    private func next() {
        if isLast { onFinish() }
        else { withAnimation(.easeInOut(duration: 0.5)) { step += 1 } }
    }

    private func back() {
        guard step > 0 else { return }
        withAnimation(.easeInOut(duration: 0.5)) { step -= 1 }
    }

    private func bindingFor(_ i: Int) -> Binding<String> {
        switch i {
        case 0: return $answers.r1
        case 1: return $answers.r2
        case 2: return $answers.r3
        case 3: return $answers.r4
        default: return $answers.r5
        }
    }
}

/// Stepped progress indicator for the reflection flow — filled capsule for the current
/// step, faint dots for the rest (continues the `PageDots` visual language).
private struct ReflectionDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == current ? 0.85 : 0.3))
                    .frame(width: i == current ? 34 : 12, height: 12)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}

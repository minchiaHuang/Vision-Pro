import SwiftUI

/// Five soft questions, one surface per step:
/// slider · image grid · icon grid · image grid · time row.
struct QuizView: View {
    @Environment(AppState.self) private var appState
    @State private var step = 0

    private var isLast: Bool { step == QuizData.stepCount - 1 }

    private var canContinue: Bool {
        switch step {
        case 1: return appState.answers.need != nil
        case 2: return appState.answers.help != nil
        case 3: return appState.answers.week != nil
        default: return true   // slider & time always have a value
        }
    }

    private var title: String {
        switch step {
        case 0: return "How is your body right now?"
        case 1: return "When you feel off-balance,\nwhat do you need?"
        case 2: return "What would help most right now?"
        case 3: return "Where in your week are you?"
        default: return "How much time do you have?"
        }
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 26) {
            ProgressPips(step: step, total: QuizData.stepCount)

            Text(title)
                .vaLargeThinTitle(size: 28)
                .lineLimit(2)
                .padding(.horizontal)

            Group {
                switch step {
                case 0:
                    SliderSurface(value: $appState.answers.energy)
                case 1:
                    ImageCardGrid(options: QuizData.need, selection: $appState.answers.need)
                case 2:
                    IconCardGrid(options: QuizData.help, selection: $appState.answers.help)
                case 3:
                    ImageCardGrid(options: QuizData.week, selection: $appState.answers.week)
                default:
                    TimeRow(options: QuizData.minutes, selection: $appState.answers.minutes)
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

// MARK: - Q1 slider

private struct SliderSurface: View {
    @Binding var value: Double
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Text("I need\nstillness")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Slider(value: $value, in: 0...1)
                    .tint(.accentColor)
                Text("I need\nenergy")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text("Drag to where you are right now")
                .font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 24)
    }
}

// MARK: - Q2 / Q4 image grid

private struct ImageCardGrid: View {
    let options: [ChoiceOption]
    @Binding var selection: String?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        if let name = option.image {
                            Image(name)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.secondary.opacity(0.2)
                        }
                        // Stronger gradient so label stays legible on light SVGs
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.35),
                                .init(color: .black.opacity(0.45), location: 0.7),
                                .init(color: .black.opacity(0.72), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Text(option.label)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                    // Aspect ratio scales with column width — no more fixed squished height
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(selectionRing(selected: selection == option.id))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Q3 icon grid

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

// MARK: - Q5 time row

private struct TimeRow: View {
    let options: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(options, id: \.self) { m in
                let isSelected = m == selection
                Button {
                    selection = m
                } label: {
                    VStack(spacing: 2) {
                        Text("\(m)").font(.title2.weight(.medium))
                        Text("min").font(.caption2)
                    }
                    .foregroundStyle(isSelected ? VATheme.onAmber : .primary)
                    .frame(width: 76, height: 76)
                    .background {
                        if isSelected {
                            Circle().fill(
                                LinearGradient(colors: [VATheme.amber, VATheme.amberDeep],
                                               startPoint: .top, endPoint: .bottom))
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: isSelected ? VATheme.amber.opacity(0.5) : .clear, radius: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 24)
    }
}

// MARK: - Shared selection ring

private func selectionRing(selected: Bool, radius: CGFloat = 22) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .stroke(selected ? VATheme.amber : .white.opacity(0.18),
                lineWidth: selected ? 2 : 0.5)
        .shadow(color: selected ? VATheme.amber.opacity(0.45) : .clear, radius: 16)
}

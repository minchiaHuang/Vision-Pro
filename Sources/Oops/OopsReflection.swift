import SwiftUI

/// 17 · Reflection (Figma "Reflection Part 1–4") — a short, passive reflective montage shown
/// after the user steps out of the 3D world. The generated world stays on screen (dimmed)
/// while three questions fade in and out one at a time, each lingering ~7 seconds. There is
/// no input — it's a quiet moment to sit with the experience — and when the last question
/// fades away the flow returns Home.
///
/// Sequence (mirrors the four Figma frames):
///   • Part 1 — the world alone, briefly, before any question (the bright opening beat)
///   • Part 2–4 — the world dimmed, each question faded in / held / faded out in turn
struct ReflectionFlowView: View {
    let onFinish: () -> Void

    private var questions: [String] { OopsContent.reflectionQuestions }

    /// Index of the question currently on screen. `-1` is the opening world-only beat (Part 1).
    @State private var index = -1
    /// Drives the current question's fade (0 → 1 → 0).
    @State private var shown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Timing (seconds). Each question is on screen ~7s total, measured from the start of its
    // fade-in: fadeIn + hold + fadeOut == questionDuration.
    private let openingBeat: Double = 2.2     // Part 1 — world only, before the first question
    private let fade: Double = 1.2
    private let questionDuration: Double = 7.0

    var body: some View {
        ZStack {
            // The generated world WITHOUT the gold picture frames — full-bleed. (The
            // frames-removed background can crop freely; there are no frames to clip.)
            Image("oops_home_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .clipped()

            // Dim scrim — light during the opening beat (Part 1), deeper once a question is up
            // (Parts 2–4) so the white text stays legible.
            Color.black.opacity(index >= 0 ? 0.45 : 0.18)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: fade), value: index)

            if index >= 0, index < questions.count {
                Text(questions[index])
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(10)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 4)
                    .padding(.horizontal, 80)
                    .frame(maxWidth: 1040)
                    .opacity(shown ? 1 : 0)
                    .id(index)                       // fresh view per question
            }
        }
        .task { await play() }
    }

    // MARK: - Playback

    @MainActor
    private func play() async {
        do {
            // Part 1 — let the world breathe before the first prompt.
            try await Task.sleep(for: .seconds(openingBeat))

            for i in questions.indices {
                index = i
                setShown(true)
                // Hold so the whole question (incl. its fade-in) lasts ~questionDuration.
                try await Task.sleep(for: .seconds(questionDuration - fade))
                setShown(false)
                try await Task.sleep(for: .seconds(fade))
            }
        } catch {
            // Cancelled because the view went away — don't navigate.
            return
        }
        onFinish()
    }

    private func setShown(_ value: Bool) {
        if reduceMotion {
            shown = value
        } else {
            withAnimation(.easeInOut(duration: fade)) { shown = value }
        }
    }
}

// MARK: - Previews

#Preview("ReflectionFlowView") {
    ReflectionFlowView(onFinish: {})
        .preferredColorScheme(.dark)
}

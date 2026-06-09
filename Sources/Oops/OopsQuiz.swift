import SwiftUI

/// 05 · Quiz — 6 questions, one per screen, paginated (Figma "Quiz Iterations").
///
/// Layout is built from **independent overlay layers** pinned to the fixed 920×530 glass
/// card, NOT a single flowing stack. This guarantees the back button (and the bottom nav)
/// land in the *exact same spot on every screen* — Q1 through Q6 — regardless of whether
/// the screen shows the tall "Quiz" header, a pill row, or a textarea:
///
///   • Back button   — top-leading, identical on all 6 screens
///   • Quiz header    — Q1 only, pinned below the back button ("Quiz" title + subtitle)
///   • Question block — question label + pills (Q1) or textarea (Q2–Q6), vertically centred
///   • Bottom nav     — "Next >" (Q1–Q5) trailing, or "Generate my world" (Q6) centred
///
/// Dimensions are proportional to the Figma card (1392×807 px) at ×0.66 scale.
///
/// Back on Q1 raises the "Are you sure?" exit dialog; back on Q2–Q6 returns to the previous
/// question. The forward control is disabled until the current question has an answer.
struct QuizScreen: View {
    @Binding var answers: OopsAnswers
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var currentIndex = 0
    @State private var confirm = false
    // Tracks the last navigation direction so the slide transition flips correctly:
    // forward (Next) slides the new card in from the trailing edge; back slides it in
    // from the leading edge. Without this the back button animated the wrong way.
    @State private var goingBack = false

    // Single horizontal inset shared by EVERY Quiz element — back arrow, "Quiz" header,
    // question label, pills and nav. Matches the Declaration card's content inset exactly:
    // that card lays its content in a 960pt column and adds 52pt padding, so all its copy
    // sits 52pt from the card edge. Using the same 52pt here gives the Quiz and the
    // Safety/Privacy screens an identical left edge.
    private let sideInset: CGFloat = 52

    // Preferred card size — matches the Safety / Privacy Declaration card's outer glass
    // footprint. That card sizes its content to 960pt then adds 52pt padding on every
    // side, so its frosted window is 960 + 52·2 = 1064pt wide (~760 tall). We match that
    // 1064pt here so the Quiz frame width follows the Declaration frame width exactly. At
    // runtime the card is capped to the available viewport (see `body`) so the frame never
    // clips on shorter screens, exactly like the content-sized Declaration card always fits.
    private let maxCardWidth: CGFloat = 1064
    private let maxCardHeight: CGFloat = 760
    private let outerMargin: CGFloat = 20

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
        // Size the card to the Privacy-matched 960×760, but never larger than the space
        // actually available — so the frame fits perfectly (no clipping) on any viewport,
        // just like the content-sized Privacy Preferences card.
        GeometryReader { geo in
            let cardW = min(maxCardWidth, geo.size.width  - outerMargin * 2)
            let cardH = min(maxCardHeight, geo.size.height - outerMargin * 2)
            let contentW = cardW - sideInset * 2

            ZStack {
                OopsPassthrough(dim: true)

                // The glass card — every element is an overlay layer pinned to its own edge,
                // so nothing reflows when the question content changes height.
                ZStack {
                    // 1 — Question block (vertically centred)
                    questionContent
                        .frame(width: contentW, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    // 2 — Q1 "Quiz" header (pinned below the back button, sharing the common
                    //     `sideInset` left edge with the back arrow and the question content).
                    if isFirst {
                        quizHeader
                            .frame(width: contentW, alignment: .leading)
                            .padding(.leading, sideInset)
                            .padding(.top, 88)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    // 3 — Back button (pinned top-leading — IDENTICAL on every screen).
                    //     Sits near the card top (top 32) so it lines up with the back chevron
                    //     on the Declaration (Safety / Privacy) screens, whose centred content
                    //     floats its chevron up to roughly the same height. Kept clear of the
                    //     "Quiz" header below it (header starts at top 88).
                    backButton
                        .padding(.leading, sideInset)
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: cardW, height: cardH)
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
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.3), value: confirm)
    }

    // MARK: - Q1 Quiz header

    /// "Quiz" bold title + descriptive subtitle — only visible on Q1. Shares the `sideInset`
    /// left edge with the question label below it.
    private var quizHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quiz")
                // Matches the Privacy Preferences title — oopsTitle(36).
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
            Text("Take a few minutes to answer these questions. Your answers will shape the world that's built for you")
                // Matches the Privacy Preferences subtitle — oopsSub(18).
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Back button

    /// Bare back chevron — no circle. The glyph is left-aligned inside a 40×40 tap target
    /// so its visual left edge sits at the overlay's `.leading` padding, giving the "Quiz"
    /// header below it a shared left edge to align to. Lives in its own overlay layer so it
    /// never moves between screens.
    private var backButton: some View {
        Button {
            if isFirst {
                confirm = true
            } else {
                goingBack = true
                withAnimation(.easeInOut(duration: 0.28)) { currentIndex -= 1 }
            }
        } label: {
            Image(systemName: "chevron.left")
                // Identical to the Declaration screen's back chevron (size 18.48, 44pt
                // leading hit target) so both screens' back buttons match exactly.
                .font(.system(size: 18.48, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Question content

    @ViewBuilder
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Matches the pointer/statement title on the Privacy & Safety screens
            // (CheckStatement head — size 20, bold); identical treatment on all 6 screens.
            Text("Qn \(currentIndex + 1): \(current.label)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if current.isTextInput {
                // Same question→answer gap as Q1 (VStack spacing 12 + 14 = 26pt).
                freeTextArea.padding(.top, 14)
            } else {
                // Extra gap to match Figma gap-[40px] between the question and the pills.
                pillRow.padding(.top, 14)
            }

            // Nav button (Next / Generate) sits directly below the answer. Q1–Q5 keep the
            // question→answer gap (VStack spacing 12 + 14 = 26pt); Q6's "Generate my world"
            // uses a 24pt top gap to match the Safety Declaration CTA's minimum spacing.
            navigationRow
                .padding(.top, isLast ? 24 : 14)
        }
        .id(currentIndex)
        .transition(.asymmetric(
            insertion: .move(edge: goingBack ? .leading : .trailing).combined(with: .opacity),
            removal:   .move(edge: goingBack ? .trailing : .leading).combined(with: .opacity)
        ))
        .animation(.easeInOut(duration: 0.28), value: currentIndex)
    }

    // MARK: - Pill row (Q1 — 4 options, fixed-width, left-packed)

    private var pillRow: some View {
        // Span the full content width and distribute the pills with Spacers so the first
        // pill sits flush against the content's left edge and the last against its right
        // edge. That makes the gap from the card to the outermost pills identical on both
        // sides (= sideInset), rather than left-packing the row and dumping all the
        // leftover space on the right.
        HStack(spacing: 0) {
            ForEach(Array(current.options.enumerated()), id: \.offset) { idx, option in
                if idx > 0 { Spacer(minLength: 20) }
                pillButton(option, selected: answers.quiz[current.id] == idx) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        answers.quiz[current.id] = idx
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Figma pill: 250×75 px → 165×50 pt; widened to 220×55 pt to tighten the inter-pill
    /// gaps now that the row spans the full content width; Capsule;
    /// white border 2.314px → 1.5pt; gradient linear(167°, white.37 → grey.42);
    /// ultraThinMaterial; drop-shadow 18%.
    private func pillButton(_ text: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                // Subheader font size (18) bumped by 2pt for stronger pill labels.
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 220, height: 55)
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
    /// px=50px → 32pt; ~32px top spacer before the placeholder hint.
    private var freeTextArea: some View {
        let binding = Binding<String>(
            get: { answers.quizText[current.id] ?? "" },
            set: { answers.quizText[current.id] = $0 }
        )
        let isEmpty = (answers.quizText[current.id] ?? "").isEmpty

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.20))

            // Placeholder hint — grey, preceded by a 21pt top spacer that reproduces the
            // 32px cursor gap Figma leaves before the hint text.
            if isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 21)
                    Text(current.placeholder)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.30))
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .allowsHitTesting(false)
            }

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

    // MARK: - Bottom navigation

    @ViewBuilder
    private var navigationRow: some View {
        if isLast {
            // Q6: "Generate my world" — the primary CTA pill, sized ~14.5% smaller than the
            // standard OopsButton (302×75 → 258.21×64.125), centred.
            Button("Generate my world", action: onFinish)
                .buttonStyle(OopsButton(fixedWidth: 258.21, fixedHeight: 64.125))
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.2), value: canAdvance)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            // Q1–Q5: "Next >" — Figma Inter Bold 20px; trailing-aligned.
            Button {
                goingBack = false
                withAnimation(.easeInOut(duration: 0.28)) { currentIndex += 1 }
            } label: {
                Text("Next >")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(canAdvance ? .white : .white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#Preview("QuizScreen") {
    QuizScreen(answers: .constant(OopsAnswers()), onFinish: {}, onBack: {})
        .preferredColorScheme(.dark)
}

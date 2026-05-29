import Foundation

/// Phase 6a — composes the entry narration the voice companion speaks when the
/// user first steps into their world. Pure text, no I/O, so it is trivially
/// unit-testable.
///
/// Design (research 方向 4 tone): warm and invitational, never evaluative.
/// It explains the world by tracing each visible feature back to what the user
/// leaned toward — framing every lean as a *direction*, not a deficiency. It
/// reads only the hidden `AxisScores` + hope direction; the open-ended free text
/// is left for the LLM-backed Phase 6b.
enum NarrationComposer {

    /// One bipolar axis with its distance from the neutral midpoint, used to
    /// surface the two most distinctive leans for this particular world.
    private struct Lean {
        let salience: Double   // |score - 0.5|; larger = more distinctive
        let order: Int         // stable tie-break (axis index)
        let sentence: String   // the spoken line for this lean
    }

    /// Builds the ~4-sentence entry narration (English, matches the app's UI).
    static func entryNarration(world: World, scores: AxisScores, params: WorldParams) -> String {
        let opening = "Take a breath. This place grew, quietly, from what you shared with me."

        // The two most distinctive leans get a sentence each, so two people
        // never hear the same introduction.
        let ranked: [Lean] = bipolarLeans(scores).sorted { a, b in
            a.salience != b.salience ? a.salience > b.salience : a.order < b.order
        }
        let leanSentences: [String] = ranked.prefix(2).map { $0.sentence }

        let closing = hopeSentence(scores.hope)

        var lines: [String] = [opening]
        lines.append(contentsOf: leanSentences)
        lines.append(closing)
        return lines.joined(separator: " ")
    }

    // MARK: - Per-axis phrasing

    private static func bipolarLeans(_ s: AxisScores) -> [Lean] {
        [
            Lean(salience: abs(s.autonomyBelonging - 0.5), order: 1,
                 sentence: s.autonomyBelonging < 0.5
                    ? "You leaned toward space of your own, so I kept the world unhurried and uncrowded — room that's simply yours."
                    : "You leaned toward closeness, so soft companions glow nearby, enough to feel held."),

            // 軸2: explore ↔ stable maps to openness (explore = open, stable = sheltered).
            Lean(salience: abs(s.exploreStable - 0.5), order: 2,
                 sentence: s.exploreStable < 0.5
                    ? "You leaned toward wandering, so the horizon opens wide, with a path that invites you onward."
                    : "You leaned toward steadiness, so the walls draw a little closer — a sheltered place to settle."),

            Lean(salience: abs(s.expressionConnection - 0.5), order: 3,
                 sentence: s.expressionConnection < 0.5
                    ? "You leaned toward your own voice, so the world stays spare and open, leaving space that's clearly yours."
                    : "You leaned toward shared life, so green and growing things fill the world, things to be among."),

            Lean(salience: abs(s.calmVivid - 0.5), order: 4,
                 sentence: s.calmVivid < 0.5
                    ? "You leaned toward calm, so the light here is low and warm, the colors soft enough to let you exhale."
                    : "You leaned toward aliveness, so the light runs bright and the colors deepen, the world awake around you.")
        ]
    }

    // MARK: - Hope direction (軸5) — the trajectory, never a verdict on now.

    private static func hopeSentence(_ hope: HopeDirection) -> String {
        let direction: String
        switch hope {
        case .ownPath: direction = "being a little more at ease as yourself"
        case .people:  direction = "drawing a little closer to others"
        case .explore: direction = "daring to wander a little further out"
        case .stable:  direction = "finding firmer, steadier ground"
        }
        return "And far off, a light marks the way you said you're moving toward — \(direction)."
    }
}

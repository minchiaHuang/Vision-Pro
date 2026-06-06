import Testing
@testable import VisitingArtisan

/// `NarrationComposer.entryNarration` is pure text: opening + the two most
/// distinctive bipolar leans (by salience, tie-broken by axis order) + a hope
/// closing. These tests pin that selection so two people never hear the same intro.
struct NarrationComposerTests {

    private let world = World(id: "w", title: "My World", imageName: "img")

    private func narration(_ s: AxisScores) -> String {
        entryNarrationText(s)
    }

    private func entryNarrationText(_ s: AxisScores) -> String {
        NarrationComposer.entryNarration(world: world, scores: s, params: WorldMapper.map(s))
    }

    @Test func alwaysOpensWithTheBreathLine() {
        let s = AxisScores.neutral
        #expect(narration(s).hasPrefix("Take a breath. This place grew, quietly, from what you shared with me."))
    }

    /// Neutral scores → all saliences equal (0); the tie-break by axis order keeps
    /// axis 1 + axis 2, and 0.5 is NOT `< 0.5`, so both take the high-pole sentence.
    @Test func neutralScoresFallBackToTheFirstTwoAxes() {
        let n = narration(.neutral)
        #expect(n.contains("You leaned toward closeness"))   // axis 1, high pole
        #expect(n.contains("You leaned toward steadiness"))  // axis 2, high pole
        #expect(!n.contains("You leaned toward your own voice"))
        #expect(!n.contains("You leaned toward calm"))
    }

    /// The two FARTHEST-from-neutral axes win. Here axis 4 (|0-0.5|=0.5) and
    /// axis 3 (|0.9-0.5|=0.4) are most distinctive; axes 1 & 2 stay neutral.
    @Test func mostDistinctiveTwoAxesAreSpoken() {
        let s = AxisScores(autonomyBelonging: 0.5, exploreStable: 0.5,
                           expressionConnection: 0.9, calmVivid: 0.0, hope: .ownPath)
        let n = narration(s)
        #expect(n.contains("You leaned toward calm"))         // axis 4, low pole
        #expect(n.contains("You leaned toward shared life"))  // axis 3, high pole (0.9)
        #expect(!n.contains("You leaned toward closeness"))   // axis 1 not distinctive
        #expect(!n.contains("You leaned toward wandering"))   // axis 2 not distinctive
    }

    @Test func closingTracesTheHopeDirection() {
        let explore = AxisScores(autonomyBelonging: 0.5, exploreStable: 0.5,
                                 expressionConnection: 0.5, calmVivid: 0.5, hope: .explore)
        #expect(narration(explore).contains("daring to wander a little further out"))

        let people = AxisScores(autonomyBelonging: 0.5, exploreStable: 0.5,
                                expressionConnection: 0.5, calmVivid: 0.5, hope: .people)
        #expect(narration(people).contains("drawing a little closer to others"))
    }
}

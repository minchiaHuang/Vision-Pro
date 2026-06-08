import Testing
@testable import VisitingArtisan

/// `Scorer.score` turns the 12 raw quiz sliders + hope string into the hidden
/// continuous `AxisScores`. Pure, no I/O — the bottom layer of the world pipeline.
struct ScorerTests {

    @Test func defaultAnswersGiveNeutralMidpoints() {
        let s = Scorer.score(QuizAnswers())   // sliders all 0.5, hope nil
        #expect(s.autonomyBelonging == 0.5)
        #expect(s.exploreStable == 0.5)
        #expect(s.expressionConnection == 0.5)
        #expect(s.calmVivid == 0.5)
        #expect(String(describing: s.hope) == "ownPath")
    }

    @Test func eachAxisIsMeanOfItsThreeSliders() {
        var a = QuizAnswers()
        a.sliders = [0.0, 0.3, 0.6,    // axis1 mean 0.3
                     1.0, 1.0, 1.0,    // axis2 mean 1.0
                     0.0, 0.0, 0.0,    // axis3 mean 0.0
                     0.2, 0.5, 0.8]    // axis4 mean 0.5
        let s = Scorer.score(a)
        #expect(abs(s.autonomyBelonging - 0.3) < 1e-9)
        #expect(abs(s.exploreStable - 1.0) < 1e-9)
        #expect(abs(s.expressionConnection - 0.0) < 1e-9)
        #expect(abs(s.calmVivid - 0.5) < 1e-9)
    }

    @Test func hopeStringMapsToDirection() {
        let cases: [(String?, String)] = [
            ("people", "people"), ("explore", "explore"), ("stable", "stable"),
            ("ownPath", "ownPath"), ("nonsense", "ownPath"), ("", "ownPath"), (nil, "ownPath"),
        ]
        for (input, expected) in cases {
            var a = QuizAnswers()
            a.hope = input
            #expect(String(describing: Scorer.score(a).hope) == expected, "hope input: \(String(describing: input))")
        }
    }

    /// A malformed slider array must fall back to `.neutral` (and therefore IGNORE
    /// the supplied hope), so a partial quiz never produces a half-scored world.
    @Test func wrongSliderCountFallsBackToNeutral() {
        var a = QuizAnswers()
        a.sliders = [0.9, 0.9]          // not 12 → guard fails
        a.hope = "people"               // would be .people if it scored normally
        let s = Scorer.score(a)
        #expect(s.autonomyBelonging == 0.5)
        #expect(s.exploreStable == 0.5)
        #expect(String(describing: s.hope) == "ownPath")
    }
}

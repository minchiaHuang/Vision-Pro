import Testing
@testable import VisitingArtisan

/// `QuizData` is the static question bank. These tests guard its internal shape
/// AND its cross-file contract with `Scorer` — e.g. there must be exactly 12
/// sliders, and every hope option id must be one `Scorer` actually recognises.
struct QuizDataTests {

    @Test func fourAxesOfThreeQuestionsMatchTheTwelveSliders() {
        #expect(QuizData.axisGroups.count == 4)
        for group in QuizData.axisGroups {
            #expect(group.count == 3)
        }
        let totalQuestions = QuizData.axisGroups.reduce(0) { $0 + $1.count }
        #expect(totalQuestions == 12)
        // The slider vector Scorer consumes must have one slot per question.
        #expect(QuizAnswers().sliders.count == totalQuestions)
    }

    @Test func everyHopeOptionIdIsRecognisedByScorerAsADistinctDirection() {
        let ids = QuizData.hopeOptions.map(\.id)
        #expect(ids == ["ownPath", "people", "explore", "stable"])

        // Feed each option id through Scorer; all four must resolve to a
        // DIFFERENT HopeDirection (a renamed id would silently fall back to
        // ownPath and collapse the set).
        var directions = Set<String>()
        for id in ids {
            var a = QuizAnswers()
            a.hope = id
            directions.insert(String(describing: Scorer.score(a).hope))
        }
        #expect(directions.count == 4)
    }

    @Test func questionIdsAreUniqueAndNonEmpty() {
        let all = QuizData.axisGroups.flatMap { $0 }
        let ids = all.map(\.id)
        #expect(Set(ids).count == ids.count)   // no duplicates
        for q in all {
            #expect(!q.id.isEmpty)
            #expect(!q.question.isEmpty)
            #expect(!q.leftLabel.isEmpty)
            #expect(!q.rightLabel.isEmpty)
        }
    }

    @Test func stepCountAndTitlesLineUpWithTheAxes() {
        // 4 axis screens + hope direction + free text.
        #expect(QuizData.stepCount == QuizData.axisGroups.count + 2)
        #expect(QuizData.axisTitles.count == QuizData.axisGroups.count)
        for option in QuizData.hopeOptions {
            #expect(!option.label.isEmpty)
            #expect(option.symbol != nil)
        }
    }
}

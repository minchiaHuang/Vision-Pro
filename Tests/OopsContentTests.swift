import Testing
@testable import VisitingArtisan

/// Data-soundness guards for the Oops flow's LIVE quiz data (`OopsContent.questions`).
///
/// This is the question set the demo actually renders (`QuizScreen` reads
/// `OopsContent.questions`); the older `QuizData`/`QuizDataTests` path is bypassed by the
/// boot-into-Oops demo. These tests pin the contract the UI and image generation rely on.
struct OopsContentTests {

    @Test func hasExactlySixQuestions() {
        #expect(OopsContent.questions.count == 6)
    }

    @Test func questionIDsAreUniqueAndNonEmpty() {
        let ids = OopsContent.questions.map(\.id)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(Set(ids).count == ids.count)   // QuizScreen keys answers by id → must be unique
    }

    @Test func everyQuestionHasALabel() {
        #expect(OopsContent.questions.allSatisfy { !$0.label.isEmpty })
    }

    @Test func onlyFirstQuestionIsPillSelectRestAreFreeText() {
        let qs = OopsContent.questions
        #expect(qs.first?.isTextInput == false)              // q1 = age pills
        #expect(qs.dropFirst().allSatisfy { $0.isTextInput }) // q2–q6 = free-text textarea
    }

    @Test func pillQuestionHasNonEmptyOptions() {
        let pill = OopsContent.questions.first { !$0.isTextInput }
        let options = try? #require(pill).options
        #expect(options?.isEmpty == false)
        #expect(options?.allSatisfy { !$0.isEmpty } == true)
    }

    @Test func freeTextQuestionsHaveAPlaceholderHint() {
        let textQuestions = OopsContent.questions.filter(\.isTextInput)
        #expect(!textQuestions.isEmpty)
        #expect(textQuestions.allSatisfy { !$0.placeholder.isEmpty })
    }

    @Test func includesIdealFutureQuestionThatDrivesImageGen() {
        // Q3's free-text answer is the `goal` fed to OpenAIImageService.generateJourney(goal:).
        let q3 = OopsContent.questions.first { $0.id == "q3" }
        #expect(q3 != nil)
        #expect(q3?.isTextInput == true)
    }
}

import Testing
import Foundation
@testable import VisitingArtisan

/// `AppState` orchestrates the quiz→loading→world transition and owns reset.
/// These tests cover the state machine without any UI.
@MainActor
struct AppStateTests {

    @Test func loadDefaultWorldPopulatesNeutralWorldWithoutTouchingPhase() {
        let state = AppState()
        state.phase = .quiz                 // some non-world phase
        state.loadDefaultWorld()

        #expect(String(describing: state.phase) == "quiz")   // phase untouched
        #expect(state.axisScores != nil)
        #expect(state.worldParams != nil)
        // Neutral scores resolve to the solitary-path archetype.
        #expect(state.world?.id == "quiet_solitary")
    }

    @Test func restartClearsEverythingBackToSplash() {
        let state = AppState()
        state.loadDefaultWorld()
        state.generatedWorldId = "w_1"
        state.generatedSplatURL = URL(string: "https://cdn.example/x.spz")
        state.answers.hope = "people"

        state.restart()

        #expect(String(describing: state.phase) == "splash")
        #expect(state.world == nil)
        #expect(state.axisScores == nil)
        #expect(state.worldParams == nil)
        #expect(state.generatedPano == nil)
        #expect(state.generatedSplatURL == nil)
        #expect(state.generatedWorldId == nil)
        #expect(state.answers.hope == nil)
    }

    @Test func finishQuizScoresThenEntersTheWorld() async throws {
        let state = AppState()
        var answers = QuizAnswers()
        answers.sliders = Array(repeating: 0.5, count: 12)
        answers.hope = "explore"
        state.answers = answers

        state.finishQuiz()
        #expect(String(describing: state.phase) == "loading")   // synchronous first beat

        // finishQuiz sleeps ~600ms before scoring + entering the world.
        try await Task.sleep(for: .seconds(2))

        #expect(String(describing: state.phase) == "world")
        #expect(state.axisScores != nil)
        #expect(state.worldParams != nil)
        #expect(state.world != nil)
        // World id is consistent with the pure pipeline run on the same answers.
        let expected = WorldCatalog.world(for: WorldMapper.map(Scorer.score(answers)).archetype)
        #expect(state.world?.id == expected.id)
    }
}

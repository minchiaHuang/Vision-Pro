import Foundation
import Observation

/// Front-end rendezvous between the Quiz screen and the floating `quiz-voice-orb` window.
///
/// The two live in separate visionOS windows, so they can't share SwiftUI `@State`; they meet
/// through this object held on `AppState`. The orb writes recognized speech into `text` for the
/// question the user is currently on (`activeQuestionID`); the Quiz screen mirrors those entries
/// into `OopsAnswers.quizText`, so typing and dictation feed the same answers. Front-end only —
/// nothing here is scored or stored.
@Observable
final class QuizVoiceSession {
    /// free-text question id → recognized answer text. Populated only by the voice orb.
    var text: [String: String] = [:]

    /// The free-text question on screen right now, or `nil` on a non-text question (e.g. the age
    /// pills). The orb refuses to dictate while this is `nil`.
    var activeQuestionID: String?

    func reset() {
        text = [:]
        activeQuestionID = nil
    }
}

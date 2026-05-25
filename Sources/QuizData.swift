import Foundation

/// v1 quiz copy. One question per dimension keeps the prototype concise.
enum QuizData {
    static let questions: [QuizQuestion] = [
        QuizQuestion(
            id: "q_emotional",
            dimension: .emotional,
            prompt: "When your balance slips, what do you reach for first?",
            options: [
                QuizOption(id: "e_quiet",   label: "Quiet space",       tag: "quiet"),
                QuizOption(id: "e_talk",    label: "Someone nearby",    tag: "connection"),
                QuizOption(id: "e_move",    label: "A physical reset",  tag: "movement"),
                QuizOption(id: "e_create",  label: "A creative outlet", tag: "creativity")
            ]
        ),
        QuizQuestion(
            id: "q_cultural",
            dimension: .cultural,
            prompt: "Where does your attention settle most naturally?",
            options: [
                QuizOption(id: "c_nature",  label: "Under open sky",    tag: "nature"),
                QuizOption(id: "c_people",  label: "With familiar people", tag: "communal"),
                QuizOption(id: "c_home",    label: "Inside a warm room", tag: "home"),
                QuizOption(id: "c_new",     label: "Somewhere undiscovered", tag: "explore")
            ]
        ),
        QuizQuestion(
            id: "q_physical",
            dimension: .physical,
            prompt: "What pace helps your body come back online?",
            options: [
                QuizOption(id: "p_still",   label: "Stillness",         tag: "still"),
                QuizOption(id: "p_active",  label: "Walking it out",    tag: "active"),
                QuizOption(id: "p_sensory", label: "Soft sensory calm", tag: "sensory"),
                QuizOption(id: "p_rest",    label: "Deep rest",         tag: "rest")
            ]
        )
    ]
}

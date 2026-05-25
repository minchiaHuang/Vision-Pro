import Foundation

/// v1 quiz 題庫（working draft — 題目設計仍需 research，見 PRD §9）。
/// 每個維度 1 題，共 3 題，剛好對應 prototype 的核心互動。
enum QuizData {
    static let questions: [QuizQuestion] = [
        QuizQuestion(
            id: "q_emotional",
            dimension: .emotional,
            prompt: "When you feel off-balance, what do you need most?",
            options: [
                QuizOption(id: "e_quiet",   label: "Quiet time alone",  tag: "quiet"),
                QuizOption(id: "e_talk",    label: "Talk to someone",   tag: "connection"),
                QuizOption(id: "e_move",    label: "Move my body",      tag: "movement"),
                QuizOption(id: "e_create",  label: "Make something",    tag: "creativity")
            ]
        ),
        QuizQuestion(
            id: "q_cultural",
            dimension: .cultural,
            prompt: "Where do you feel most like yourself?",
            options: [
                QuizOption(id: "c_nature",  label: "In nature",         tag: "nature"),
                QuizOption(id: "c_people",  label: "Around people",     tag: "communal"),
                QuizOption(id: "c_home",    label: "At home",           tag: "home"),
                QuizOption(id: "c_new",     label: "Somewhere new",     tag: "explore")
            ]
        ),
        QuizQuestion(
            id: "q_physical",
            dimension: .physical,
            prompt: "How does your body recharge?",
            options: [
                QuizOption(id: "p_still",   label: "Stillness",         tag: "still"),
                QuizOption(id: "p_active",  label: "Movement",          tag: "active"),
                QuizOption(id: "p_sensory", label: "Sensory calm",      tag: "sensory"),
                QuizOption(id: "p_rest",    label: "Rest",              tag: "rest")
            ]
        )
    ]
}

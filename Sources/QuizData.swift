import Foundation

/// v1 quiz copy for the five soft questions (slider, image grid, icon grid, image grid, time row).
enum QuizData {

    // Q2 — "When you feel off-balance, what do you need?" (image grid; Claude-designed scenes)
    static let need: [ChoiceOption] = [
        ChoiceOption(id: "quiet",      label: "Quiet",      image: "scene_forest"),
        ChoiceOption(id: "connection", label: "Connection", image: "scene_cafe"),
        ChoiceOption(id: "movement",   label: "Movement",   image: "scene_run"),
        ChoiceOption(id: "creativity", label: "Creativity", image: "scene_sketch")
    ]

    // Q3 — "What would help most right now?" (icon grid; SF Symbols)
    static let help: [ChoiceOption] = [
        ChoiceOption(id: "alone", label: "Quiet time alone", symbol: "person"),
        ChoiceOption(id: "talk",  label: "Talk to someone",  symbol: "person.2.fill"),
        ChoiceOption(id: "move",  label: "Move my body",     symbol: "figure.run"),
        ChoiceOption(id: "make",  label: "Make something",   symbol: "paintbrush.pointed")
    ]

    // Q4 — "Where in your week are you?" (image grid; Claude-designed scenes)
    static let week: [ChoiceOption] = [
        ChoiceOption(id: "exam",  label: "Before an exam",         image: "scene_focus"),
        ChoiceOption(id: "sleep", label: "Winding down for sleep", image: "scene_nightstudy"),
        ChoiceOption(id: "home",  label: "Missing home",           image: "scene_empty"),
        ChoiceOption(id: "focus", label: "Need to focus",          image: "scene_sketch")
    ]

    // Q5 — "How much time do you have?" (time row)
    static let minutes: [Int] = [5, 10, 15, 20, 30]

    /// Total number of question steps.
    static let stepCount = 5
}

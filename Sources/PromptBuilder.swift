import Foundation

/// Builds a text prompt from the quiz answers.
/// Not wired into the UI yet; kept for a future World Labs / Skybox hookup.
enum PromptBuilder {

    private static let needFragment: [String: String] = [
        "quiet":      "calm and serene",
        "connection": "warm and inviting",
        "movement":   "energetic and open",
        "creativity": "soft, imaginative light"
    ]

    private static let weekFragment: [String: String] = [
        "exam":  "a focused, lamp-lit interior",
        "sleep": "a quiet space for winding down",
        "home":  "an open, familiar landscape",
        "focus": "a still, distraction-free place"
    ]

    static func prompt(from answers: QuizAnswers) -> String {
        var parts: [String] = []
        let energyWord = answers.energy < 0.35 ? "stillness"
            : (answers.energy > 0.65 ? "bright energy" : "warm focus")
        parts.append(energyWord)
        if let need = answers.need, let f = needFragment[need] { parts.append(f) }
        if let week = answers.week, let f = weekFragment[week] { parts.append(f) }
        let body = parts.joined(separator: ", ")
        return "An immersive 360 environment that feels \(body)."
    }
}

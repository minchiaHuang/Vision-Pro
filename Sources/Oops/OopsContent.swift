import Foundation

/// Static copy for the Oops flow, transcribed verbatim from the prototype
/// (`onboarding.jsx`, `quiz.jsx`, `world.jsx`).
enum OopsContent {

    struct Statement: Identifiable {
        let id = UUID()
        let head: String
        let text: String
    }

    static let safety: [Statement] = [
        .init(head: "Your Consent & Data",
              text: "Your quiz answers personalise your world in real time and are never stored or shared. Camera and motion data is used solely for movement and is never recorded."),
        .init(head: "Emotional Safety",
              text: "This is a reflective simulation based on your values — not a judgement of who you are. If anything feels difficult, pause or exit at any time."),
        .init(head: "Physical Safety",
              text: "Some users may feel dizzy or nauseous. Ensure you have clear space around you, and exit immediately if you feel any discomfort."),
    ]

    static let privacy: [Statement] = [
        .init(head: "Quiz Responses",
              text: "Your answers can be saved to personalise your experience across future sessions. If you'd prefer not, they'll be used in real time only and discarded when your session ends."),
        .init(head: "Device Motion",
              text: "Gyroscope and accelerometer data can be saved to improve how you move through your world over time. If you'd rather not, it stays on your device and is never transmitted."),
        .init(head: "Image Access",
              text: "Camera data can be saved to refine your AR experience in future sessions. If you decline, it's used solely for live spatial awareness and no images or video are ever captured or stored."),
    ]

    /// One quiz question. `options` non-empty → pill selection; empty → free-text textarea.
    /// `placeholder` is shown as hint text inside the textarea (ignored for pill questions).
    struct Question: Identifiable {
        let id: String
        let label: String
        let options: [String]       // empty means free-text input
        let placeholder: String     // hint text for text input screens
        var isTextInput: Bool { options.isEmpty }
    }

    /// 6 questions (one per screen), exactly matching the Figma "Quiz Iterations" design.
    /// Q1: pill-select (age) — shows the "Quiz" header + subtitle.
    /// Q2–Q6: free-text textarea — no header, just the question + input.
    /// Q3 ("ideal future") drives the Hero's Journey image generation.
    /// Q6 is the final step — shows "Generate my world" instead of "Next >".
    static let questions: [Question] = [
        .init(id: "q1",
              label: "How old are you?",
              options: ["< 18", "18-25", "25-30", ">30"],
              placeholder: ""),
        .init(id: "q2",
              label: "Where do you live?",
              options: [],
              placeholder: "Say something…"),
        .init(id: "q3",
              label: "What's your ideal future like? Who do you want to become?",
              options: [],
              placeholder: "Share as much details as you can. The more context you give, the better the outcome"),
        .init(id: "q4",
              label: "What would you describe your current self as?",
              options: [],
              placeholder: "Share as much details as you can. The more context you give, the better the outcome"),
        .init(id: "q5",
              label: "What is the biggest thing standing between you and your ideal self?",
              options: [],
              placeholder: "Share as much details as you can. The more context you give, the better the outcome"),
        .init(id: "q6",
              label: "Lastly, what are you least willing to give up for it?",
              options: [],
              placeholder: "Share as much details as you can. The more context you give, the better the outcome"),
    ]

    // Reflection copy (Figma "Reflection Part 1–4") — a passive montage shown after the user
    // steps out of the 3D world: the generated world stays on screen (dimmed) while these
    // three prompts fade in and out one at a time, each lingering ~5s. No input — purely a
    // quiet moment to sit with the experience. Line breaks match the Figma frames.
    static let reflectionQuestions: [String] = [
        "If no one could see this world,\nWould you still want it?",
        "Did this world feel fulfilling,\nor simply impressive?",
        "Which part of this world\ngenuinely felt like you?",
    ]

    static let declarationIntro = "Before you step in, here are a few things we want you to know, so you can feel safe, comfortable, and fully present in your experience."

    /// Privacy Preferences subtitle (Figma node 49:2173) — distinct from the Safety intro.
    static let privacyIntro = "Select what you are comfortable sharing with us."
}

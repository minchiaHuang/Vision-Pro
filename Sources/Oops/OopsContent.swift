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
              text: "Your quiz answers are used only to match you to a personalised world — they are processed in real time and never stored, shared, or used beyond this session. Camera and motion access are used solely to let you move through your world and are never recorded."),
        .init(head: "Emotional Safety",
              text: "What you're about to experience is a reflective simulation based on your values and aspirations, not a forecast of your future or a judgement of who you are. If anything brings up difficult emotions, you are welcome to pause or exit at any time."),
        .init(head: "Physical Safety",
              text: "Some users may experience dizziness or nausea during immersive experiences. Please ensure you have clear space around you before you begin, and if you feel any discomfort at any point, exit the experience immediately."),
    ]

    static let privacy: [Statement] = [
        .init(head: "Quiz Responses",
              text: "Your answers are used in real time to match you to a personalised world. They are never stored after your session ends."),
        .init(head: "Device Motion",
              text: "Gyroscope and accelerometer data lets you look around and walk through your world. This data stays on your device and is never transmitted."),
        .init(head: "Images Access",
              text: "Used for AR movement and spatial awareness within your world. No images or video are captured or stored at any point."),
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
              options: ["17 - 20", "20-25", "25-30", "> 30"],
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
              label: "What are you least willing to give up for it?",
              options: [],
              placeholder: "Share as much details as you can. The more context you give, the better the outcome"),
    ]

    // Reflection copy (frames 17–21) — shown one question per screen after the user
    // steps out of the 3D world. Free-text only; front-end, never stored or scored.
    static let reflectionEyebrow = "YOUR REFLECTION"
    static let reflectionPlaceholder = "Write your thoughts here…"
    static let reflectionQuestions: [String] = [
        "Walking out of that world, what was the first feeling that hit you?",
        "You came here for stillness. Did you find it in there?",
        "Was there a moment inside that felt completely, quietly right — like “yes this is me”? What was happening in that moment?",
        "Was there anything that felt off, or not quite you? Even something small.",
        "If there’s one thing you could change for this world we built for you, what would it be?",
    ]

    static let declarationIntro = "Before you step in, here are a few things we want you to know, so you can feel safe, comfortable, and fully present in your experience."
}

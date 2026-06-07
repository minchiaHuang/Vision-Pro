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

    /// The 4 quiz questions. Each is single-select with four options.
    struct Question: Identifiable {
        let id: String
        let label: String
        let options: [String]
    }

    static let questions: [Question] = [
        .init(id: "q1",
              label: "When your schedule is completely empty, you feel:",
              options: [
                "Relief : finally, space to breathe",
                "Restless : you need something to fill it",
                "Peaceful : you settle into the quiet naturally",
                "Uncomfortable : you need something to fill it",
              ]),
        .init(id: "q2",
              label: "Your mind at its natural state is closest to:",
              options: [
                "A still lake, occasional ripples",
                "A busy street, always something moving",
                "A quiet garden, slow and unhurried",
                "A live wire, buzzing with thoughts",
              ]),
        .init(id: "q3",
              label: "When something unexpected happens, your first instinct is...",
              options: [
                "Pause and recalibrate",
                "React and keep moving",
                "Take a breath and observe first",
                "Jump straight into solving it",
              ]),
        .init(id: "q4",
              label: "You feel most like yourself when ...",
              options: [
                "You have time to think before you speak",
                "You are thinking out loud in the middle of things",
                "Life has a gentle, predictable rhythm",
                "there's something new that demands your attention",
              ]),
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

    // Preview screen copy.
    static let previewTitle = "Quiet Meadow"
    static let previewBody = "This is what you needed. Not loud, not busy. Just stillness that actually feels like relief. Somewhere between the grass and the golden sky, time slows down and the weight of everything lifts, just a little. This is the quiet you've been carrying around, waiting to find."

    static let declarationIntro = "Before you step in, here are a few things we want you to know, so you can feel safe, comfortable, and fully present in your experience."
}

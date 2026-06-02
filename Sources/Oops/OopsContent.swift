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

    /// The 6 reflective questions. `kind` selects the input control.
    enum QKind { case text, slider, area }
    struct Question: Identifiable {
        let id: String
        let label: String
        let kind: QKind
        var placeholder: String = ""
        var hasMic: Bool = false
    }

    static let questions: [Question] = [
        .init(id: "q1", label: "Question 1: What is the meaning of life?",
              kind: .text, placeholder: "To find my passion", hasMic: true),
        .init(id: "q2", label: "Question 2: From a scale from 1 to 10", kind: .slider),
        .init(id: "q3", label: "Question 3: What are your priorities?",
              kind: .text, placeholder: "Family, calm, a little adventure…"),
        .init(id: "q4", label: "Question 4: Who's in the room, or nearby? What's the energy like between you? (Companionship, laughter, focus?)",
              kind: .area, placeholder: "Describe who's there with you…"),
        .init(id: "q5", label: "Question 5: What's the thing you're working towards that makes the hard days feel worth it? (What pulls you forward?)",
              kind: .area, placeholder: "What keeps you going…"),
        .init(id: "q6", label: "Question 6: When you picture this place, what's the one feeling you want it to hold?",
              kind: .text, placeholder: "Stillness, warmth, possibility…"),
    ]

    // Preview screen copy.
    static let previewTitle = "Quiet Meadow"
    static let previewBody = "This is what you needed. Not loud, not busy. Just stillness that actually feels like relief. Somewhere between the grass and the golden sky, time slows down and the weight of everything lifts, just a little. This is the quiet you've been carrying around, waiting to find."

    static let declarationIntro = "Before you step in, here are a few things we want you to know, so you can feel safe, comfortable, and fully present in your experience."
}

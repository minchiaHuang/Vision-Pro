import Foundation

/// Future Museum — data model.
///
/// The pipeline is two stages:
///   Stage A (`CuratorService`)  : `MuseumAnswers` → `MuseumStory` (5 Hero's-Journey beats)
///   Stage B (`ImageGenerationService`) : each `MuseumNode.image_prompt` → image `Data`
///
/// `GeneratedNode` pairs a beat with its (eventually) generated image so the gallery can
/// stream images in one card at a time.

/// Typed answers collected from the Future Museum question form (front-end only — never
/// stored). Only `role` is required; blank optional fields are inferred by the Curator
/// from the archetype.
struct MuseumAnswers {
    var role = ""        // Q1 — "Who do you want to become?" (required; the Call)
    var age = 22         // anchor — the Ordinary World's starting point
    var city = ""        // anchor — localizes the Elixir (e.g. Sydney Opera House)
    var currentSelf = "" // anchor — who they are now (enriches the Ordinary World beat)
    var fear = ""        // Q2 — "What's been stopping you?" (the Refusal)
    var sacrifice = ""   // Q3 — "What are you least willing to give up?" (the Ordeal)
    var worthIt = ""     // Q4 — "What would make it worth it, even if you never make it?"

    /// The plain-text block sent as the final user turn to the Curator (Stage A).
    var promptInput: String {
        """
        role: \(role)
        age: \(age)
        city: \(city)
        current_self: \(currentSelf)
        fear: \(fear)
        sacrifice: \(sacrifice)
        worth_it: \(worthIt)
        """
    }
}

/// One Hero's-Journey beat returned by Stage A. Field names match the Curator JSON schema
/// verbatim so `JSONDecoder` maps them directly.
struct MuseumNode: Codable, Sendable, Identifiable {
    let stage: String        // ordinary_world_call | crossing_threshold | ordeal | sacrifice | return_elixir
    let age: Int
    let beat: String
    let caption: String      // short museum wall-label shown on the plaque beside the picture (≠ narration)
    let narration: String
    let image_prompt: String // self-contained — already includes the style string
    let tone: String         // "cold" (the 4 cost beats) | "warm" (the elixir)

    var id: String { stage }
}

/// The full 5-beat story returned by Stage A.
struct MuseumStory: Codable, Sendable {
    let persona: String
    let cold_style: String
    let warm_style: String
    let decision_prompt: String
    let refusal: String?     // non-nil only if the Curator declined the goal
    let nodes: [MuseumNode]
}

/// Runtime pairing of a beat with its generated image. `@Observable` so a single card
/// re-renders the moment its image lands, while the rest are still painting.
@MainActor
@Observable
final class GeneratedNode: Identifiable {
    nonisolated let id: String
    nonisolated let node: MuseumNode
    var image: Data?
    var failed = false

    init(node: MuseumNode) {
        self.id = node.id
        self.node = node
    }
}

// MARK: - Sample beats (preview / "Visit Old World" without running generation)

/// Stand-in beats so the BA396 plaques can be shown — and the Curator voice grounded — via
/// "Visit Old World" (or dev entry) without running the quiz + image generation. Six entries (one
/// per wall) with deliberately mixed caption lengths so the plaque layout/size can be judged on
/// both short and long labels. Used only when `appState.museumStory` is nil; the real flow always
/// supplies its own story.
enum BeatPlaqueSample {
    static let nodes: [MuseumNode] = [
        .init(stage: "ordinary_world_call", age: 17, beat: "",
              caption: "The Drawer — where the dream is kept, unspoken.",
              narration: "Seventeen. You keep the flyer in a drawer. You haven't told anyone yet.",
              image_prompt: "", tone: "cold"),
        .init(stage: "crossing_threshold", age: 19, beat: "",
              caption: "Before Dawn",
              narration: "Then, for years, every morning before the city wakes. No audience. No applause.",
              image_prompt: "", tone: "cold"),
        .init(stage: "ordeal", age: 23, beat: "",
              caption: "The Empty Row — when the body fails and the others have gone.",
              narration: "Twenty-three. Your body gives out. The ones who started with you have already left.",
              image_prompt: "", tone: "cold"),
        .init(stage: "sacrifice", age: 27, beat: "",
              caption: "Missed Calls",
              narration: "You wanted to keep time with your family. You missed the last birthday that mattered.",
              image_prompt: "", tone: "cold"),
        .init(stage: "return_elixir", age: 34, beat: "",
              caption: "Curtain Call — one stage, at last.",
              narration: "Thirty-four. The Opera House. Whether it was worth it — only you will know.",
              image_prompt: "", tone: "warm"),
        .init(stage: "epilogue", age: 40, beat: "",
              caption: "After — a sample sixth label for sizing.",
              narration: "A sixth sample beat so all six BA396 walls show a plaque for layout checking.",
              image_prompt: "", tone: "warm"),
    ]

    /// A full sample story wrapping `nodes`, used to ground the Curator voice in "Visit Old World"
    /// so the wall-plaque play button (`ConversationService.describeExhibit`) and the push-to-talk
    /// orb are testable without running the quiz + generation. Not used in the real flow.
    static let story = MuseumStory(
        persona: "a dancer who gave everything to one stage",
        cold_style: "",
        warm_style: "",
        decision_prompt: "Knowing the cost laid out in these rooms, would you still begin?",
        refusal: nil,
        nodes: nodes
    )
}

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

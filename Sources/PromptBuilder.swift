import Foundation

/// Builds a Skybox AI text prompt from `WorldParams`.
/// Not wired into the UI yet; kept for a future Skybox / World Labs hookup (v5).
/// Follows the prompt structure from doc/self_alignment_skybox_prompt_templates.md.
enum PromptBuilder {

    private static let axis4Phrases: [String: String] = [
        "low":  "soft desaturated cool palette, muted teal and lavender, gentle diffuse low light, low contrast, calming",
        "mid":  "balanced natural palette, warm neutral beige and soft gold, natural daylight, medium contrast",
        "high": "vivid saturated warm palette, glowing coral and amber, bright directional morning sunlight, high contrast, energetic",
    ]
    private static let axis1Phrases: [String: String] = [
        "low":  "solitary open space, no people, a single distant figure on the horizon",
        "mid":  "a few distant human silhouettes, occasional meeting points",
        "high": "warm gathering with glowing lanterns, an inviting communal settlement, a sheltered nook",
    ]
    private static let axis2Phrases: [String: String] = [
        "low":  "wide open horizon, distant vista, winding paths inviting forward (high prospect), with one small refuge",
        "mid":  "a far vista balanced with a sheltered resting spot",
        "high": "clear bounded sheltered enclosure (high refuge), structured and predictable, one opening outward",
    ]
    private static let axis3Phrases: [String: String] = [
        "low":  "a unique landmark with distinct personal organic forms, a signed space of one's own",
        "mid":  "balanced natural and crafted elements, personal and shared coexisting",
        "high": "lush shared greenery, a nurturing circular natural settlement, restorative biophilic forms",
    ]
    private static let hopePhrases: [HopeDirection: String] = [
        .ownPath: "in the far distance a clear sunlit path of one's own extending outward",
        .people:  "in the far distance warm glowing lights of a welcoming settlement",
        .explore: "in the far distance an unfolding new horizon yet to be explored",
        .stable:  "in the far distance the solid reassuring outline of a home to belong to",
    ]
    private static let suffix = "equirectangular 360 panorama, first-person eye level, atmospheric depth, highly detailed, cinematic soft focus, no readable text, no human faces."

    static func prompt(from params: WorldParams, archetypeName: String = "this world") -> String {
        let parts: [String] = [
            "A world of \(archetypeName)",
            axis2Phrases[bucket(params.openness)] ?? "",
            axis1Phrases[bucket(Double(params.socialDensity) / 8)] ?? "",
            axis3Phrases[bucket(params.biophilicDensity)] ?? "",
            axis4Phrases[bucket(params.saturation - 0.5)] ?? "",
            hopePhrases[params.focal] ?? "",
            suffix,
        ]
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func bucket(_ x: Double) -> String {
        x < 0.34 ? "low" : (x < 0.67 ? "mid" : "high")
    }
}

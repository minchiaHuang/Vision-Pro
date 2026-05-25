import Foundation

/// v1 world presets and lookup-based resolution.
/// v2 can replace resolve() with live Skybox generation.
enum WorldCatalog {

    /// Bundled worlds. imageName must match the asset catalog names.
    static let all: [World] = [
        World(
            id: "calm_communal",
            title: "A Room That Lets You Exhale",
            imageName: "world_calm_communal",
            blurb: "Warm light, familiar textures, and enough company to feel held."
        ),
        World(
            id: "open_nature",
            title: "A Horizon With Room to Move",
            imageName: "world_open_nature",
            blurb: "Open air, soft distance, and a path that gives your body space."
        ),
        World(
            id: "quiet_solitary",
            title: "A Night Made for Quiet",
            imageName: "world_quiet_solitary",
            blurb: "Low city light, deep stillness, and space to return to yourself."
        )
    ]

    /// Fallback world, so the flow still completes if resolution misses.
    static let fallback = World(
        id: "fallback",
        title: "A Place to Begin Again",
        imageName: "world_calm_communal",
        blurb: "Your space."
    )

    /// Resolve a world from quiz tags.
    /// v1 stays simple: emotional, cultural, and physical tags choose a preset.
    static func resolve(from result: QuizResult) -> World {
        let emotional = result.tag(for: .emotional) ?? ""
        let cultural = result.tag(for: .cultural) ?? ""
        let physical = result.tag(for: .physical) ?? ""

        switch (emotional, cultural, physical) {
        case ("quiet", _, _):
            return byId("quiet_solitary")
        case (_, "communal", _), (_, "home", _):
            return byId("calm_communal")
        case (_, _, "still"), (_, _, "rest"):
            return byId("quiet_solitary")
        case (_, _, "active"), (_, "explore", _), (_, "nature", _):
            return byId("open_nature")
        default:
            return fallback
        }
    }

    private static func byId(_ id: String) -> World {
        all.first { $0.id == id } ?? fallback
    }
}

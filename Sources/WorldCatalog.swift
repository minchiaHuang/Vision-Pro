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

    /// Resolve one of the three preset worlds from the five answers.
    /// Priority: week (context) → need/help → energy. Mapping is tunable;
    /// it is a product decision (see PRD §9) and starts from this baseline.
    static func resolve(from answers: QuizAnswers) -> World {
        // 1) Weekly context wins.
        switch answers.week {
        case "sleep":        return byId("quiet_solitary")
        case "home":         return byId("open_nature")
        case "exam", "focus": return byId("calm_communal")
        default: break
        }

        // 2) What they need / what helps.
        if answers.need == "quiet" || answers.help == "alone" {
            return byId("quiet_solitary")
        }
        if answers.need == "connection" || answers.help == "talk" {
            return byId("calm_communal")
        }
        if answers.need == "movement" || answers.help == "move"
            || answers.need == "creativity" || answers.help == "make" {
            return byId("open_nature")
        }

        // 3) Fall back to body energy.
        if answers.energy < 0.35 { return byId("quiet_solitary") }
        if answers.energy > 0.65 { return byId("open_nature") }
        return fallback
    }

    private static func byId(_ id: String) -> World {
        all.first { $0.id == id } ?? fallback
    }
}

import Foundation

/// v1 world presets and lookup-based resolution.
/// v2 can replace resolve() with live Skybox generation.
enum WorldCatalog {

    /// Bundled worlds. imageName must match the asset catalog names.
    /// Assets to be sourced (Week 1): world_starry_night, world_warm_communal.
    /// Existing assets used: world_open_nature, world_quiet_solitary.
    static let all: [World] = [
        World(
            id: "starry_night",
            title: "Under a Sky Made of Quiet",
            imageName: "world_starry_night",
            blurb: "A cosmos that holds you without needing anything back.",
            narrationText: ""
        ),
        World(
            id: "open_nature",
            title: "A Horizon With Room to Move",
            imageName: "world_open_nature",
            blurb: "Open air, soft distance, and a path that gives your body space.",
            narrationText: "",
            sceneName: "world_open_nature"
        ),
        World(
            id: "warm_communal",
            title: "A Room That Lets You Exhale",
            imageName: "world_warm_communal",
            blurb: "Warm light, familiar textures, and enough company to feel held.",
            narrationText: "",
            sceneName: "world_warm_communal"
        ),
        World(
            id: "quiet_solitary",
            title: "A Quiet Worth Returning To",
            imageName: "world_quiet_solitary",
            blurb: "Soft light, still air, and space to hear yourself again.",
            narrationText: ""
        )
    ]

    /// Fallback world, so the flow still completes if resolution misses.
    static let fallback = World(
        id: "fallback",
        title: "A Place to Begin Again",
        imageName: "world_warm_communal",
        blurb: "Your space."
    )

    /// Resolve one of the four preset worlds from the five answers.
    /// Priority: night + solitary → starry; communal cues → warm room;
    /// active/outdoor cues → open nature; quiet/focus/low energy → solitary.
    /// Mapping is a product decision (see PRD §9) and starts from this baseline.
    static func resolve(from answers: QuizAnswers) -> World {
        let isSolitary = answers.need == "quiet" || answers.help == "alone"
        let isCommunal = answers.need == "connection" || answers.help == "talk"
        let isActive = answers.need == "movement" || answers.need == "creativity"
            || answers.help == "move" || answers.help == "make"
            || answers.energy > 0.65
        let isLowEnergy = answers.energy < 0.35

        // 1) Night context + solitary cue → cosmic / Sky Guide vibe.
        if answers.week == "sleep" && isSolitary {
            return byId("starry_night")
        }

        // 2) Communal cues → warm indoor space.
        if answers.week == "home" || isCommunal {
            return byId("warm_communal")
        }

        // 3) Active / outdoor cues → open nature.
        if isActive {
            return byId("open_nature")
        }

        // 4) Quiet / focus / low energy → minimal solo space.
        if isSolitary || isLowEnergy
            || answers.week == "exam" || answers.week == "focus"
            || answers.week == "sleep" {
            return byId("quiet_solitary")
        }

        return fallback
    }

    private static func byId(_ id: String) -> World {
        all.first { $0.id == id } ?? fallback
    }
}

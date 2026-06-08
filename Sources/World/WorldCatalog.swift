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

    /// Returns the `World` whose title/blurb matches the given archetype,
    /// aligning overlay copy with the USDZ scene the user actually sees.
    static func world(for archetype: WorldArchetype) -> World {
        switch archetype {
        case .openNature:   return byId("open_nature")
        case .cozyCommunal: return byId("calm_communal")
        case .solitaryPath: return byId("quiet_solitary")
        case .artGallery:   return fallback   // gallery uses its own Oops copy, not a World object
        }
    }

    private static func byId(_ id: String) -> World {
        all.first { $0.id == id } ?? fallback
    }
}

// MARK: - Continuous scoring + mapping (research direction 6 → direction 7)

/// Turns the research 4+1 axis quiz answers into the hidden continuous `AxisScores`.
/// Each axis is the mean of its 3 this-or-that sliders (each already 0...1).
enum Scorer {
    static func score(_ a: QuizAnswers) -> AxisScores {
        guard a.sliders.count == 12 else { return .neutral }
        let axis1 = (a.sliders[0] + a.sliders[1] + a.sliders[2]) / 3
        let axis2 = (a.sliders[3] + a.sliders[4] + a.sliders[5]) / 3
        let axis3 = (a.sliders[6] + a.sliders[7] + a.sliders[8]) / 3
        let axis4 = (a.sliders[9] + a.sliders[10] + a.sliders[11]) / 3
        let hope: HopeDirection
        switch a.hope {
        case "people":  hope = .people
        case "explore": hope = .explore
        case "stable":  hope = .stable
        default:        hope = .ownPath
        }
        return AxisScores(autonomyBelonging: axis1, exploreStable: axis2,
                          expressionConnection: axis3, calmVivid: axis4, hope: hope)
    }
}

/// Maps the hidden `AxisScores` to concrete `WorldParams` for the display layer.
/// Values follow the research direction 7 mapping table; tune the constants freely.
enum WorldMapper {
    static func map(_ s: AxisScores) -> WorldParams {
        let calm = clamp01(s.calmVivid)
        // axis 2: explore = open, stable = enclosed. Clamp so the world is NEVER
        // fully open (always one refuge) nor fully sealed (always one opening)
        // — an iron rule of the research direction 7 mapping.
        let openness = clamp(1 - s.exploreStable, low: 0.15, high: 0.95)
        let biophilic = lerp(0.3, 1.0, clamp01(s.expressionConnection))

        return WorldParams(
            archetype: archetype(openness: openness,
                                 belonging: s.autonomyBelonging,
                                 biophilic: biophilic),
            lightIntensity: Float(lerp(500, 3000, calm)),     // calm dim … vivid bright
            colorTemperature: Float(lerp(7000, 3500, calm)),  // calm cool … vivid warm (K)
            saturation: lerp(0.5, 1.1, calm),                 // calm desaturated … vivid saturated
            socialDensity: Int(lerp(0, 8, clamp01(s.autonomyBelonging)).rounded()),
            openness: openness,
            biophilicDensity: biophilic,
            focal: s.hope
        )
    }

    /// Coarse base from the structural axes (research: pick base, then tune).
    private static func archetype(openness: Double, belonging: Double, biophilic: Double) -> WorldArchetype {
        if openness >= 0.6 { return .openNature }
        if belonging >= 0.55 || biophilic >= 0.7 { return .cozyCommunal }
        return .solitaryPath
    }
}

// Shared numeric helpers for scoring/mapping.
private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
private func clamp(_ x: Double, low: Double, high: Double) -> Double { min(max(x, low), high) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * clamp01(t) }

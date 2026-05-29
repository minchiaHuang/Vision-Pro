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

    /// Returns the `World` whose title/blurb matches the given archetype,
    /// aligning overlay copy with the USDZ scene the user actually sees.
    static func world(for archetype: WorldArchetype) -> World {
        switch archetype {
        case .openNature:   return byId("open_nature")
        case .cozyCommunal: return byId("calm_communal")
        case .solitaryPath: return byId("quiet_solitary")
        }
    }

    private static func byId(_ id: String) -> World {
        all.first { $0.id == id } ?? fallback
    }
}

// MARK: - Continuous scoring + mapping (research 方向 6 → 方向 7)

/// Turns the quiz answers into the hidden continuous `AxisScores`.
/// NOTE: this is an INTERIM read of the v1 five-question quiz so the whole
/// pipeline runs end-to-end now. Phase 5 replaces it with the research 4+1
/// question bank (`doc/self_alignment_3d_world_quiz_questions.md`).
enum Scorer {
    static func score(_ a: QuizAnswers) -> AxisScores {
        // 軸4 平靜↔生機: the energy slider already runs 0 (stillness) … 1 (energy).
        let calmVivid = clamp01(a.energy)

        // 軸1 自主↔歸屬: alone/quiet lean autonomy; talk/connection lean belonging.
        var autonomyBelonging = 0.5
        if a.help == "alone" || a.need == "quiet" { autonomyBelonging = 0.15 }
        if a.help == "talk" || a.need == "connection" { autonomyBelonging = 0.85 }

        // 軸3 自我表達↔集體連結: make/creativity lean expression; talk/connection lean connection.
        var expressionConnection = 0.5
        if a.help == "make" || a.need == "creativity" { expressionConnection = 0.2 }
        if a.help == "talk" || a.need == "connection" { expressionConnection = 0.8 }

        // 軸2 探索↔穩定: movement/creativity lean explore; exam/focus/sleep lean stable.
        var exploreStable = 0.5
        if a.need == "movement" || a.help == "move" || a.need == "creativity" { exploreStable = 0.25 }
        if a.week == "exam" || a.week == "focus" || a.week == "sleep" { exploreStable = 0.75 }

        // 軸5 希望方向: a light read of what they reached for (never a deficit).
        let hope: HopeDirection
        switch a.need {
        case "connection": hope = .people
        case "movement":   hope = .explore
        case "quiet":      hope = .stable
        default:           hope = .ownPath   // creativity / unset
        }

        return AxisScores(
            autonomyBelonging: autonomyBelonging,
            exploreStable: exploreStable,
            expressionConnection: expressionConnection,
            calmVivid: calmVivid,
            hope: hope
        )
    }
}

/// Maps the hidden `AxisScores` to concrete `WorldParams` for the display layer.
/// Values follow the research 方向 7 mapping table; tune the constants freely.
enum WorldMapper {
    static func map(_ s: AxisScores) -> WorldParams {
        let calm = clamp01(s.calmVivid)
        // 軸2: explore = open, stable = enclosed. Clamp so the world is NEVER
        // fully open (always one refuge) nor fully sealed (always one opening)
        // — research 方向 7 鐵則.
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

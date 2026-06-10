import Testing
@testable import VisitingArtisan

/// `WorldMapper.map` is the product's brain: hidden `AxisScores` → concrete
/// `WorldParams`. These tests pin the research-direction-7 mapping constants so a
/// stray edit can't silently generate the wrong world.
struct WorldMapperTests {

    private func scores(autonomy: Double = 0.5, explore: Double = 0.5,
                        expression: Double = 0.5, calm: Double = 0.5,
                        hope: HopeDirection = .ownPath) -> AxisScores {
        AxisScores(autonomyBelonging: autonomy, exploreStable: explore,
                   expressionConnection: expression, calmVivid: calm, hope: hope)
    }

    // MARK: - The "iron rule": openness is never fully open nor fully sealed.

    @Test func opennessIsClampedToTheIronRuleRange() {
        let mostOpen = WorldMapper.map(scores(explore: 0.0))   // 1 - 0 = 1 → clamp 0.95
        #expect(abs(mostOpen.openness - 0.95) < 1e-9)

        let mostSealed = WorldMapper.map(scores(explore: 1.0)) // 1 - 1 = 0 → clamp 0.15
        #expect(abs(mostSealed.openness - 0.15) < 1e-9)

        for e in stride(from: 0.0, through: 1.0, by: 0.1) {
            let o = WorldMapper.map(scores(explore: e)).openness
            #expect(o >= 0.15 && o <= 0.95, "openness escaped iron-rule range at explore=\(e)")
        }
    }

    // MARK: - Archetype selection thresholds.

    @Test func wideOpennessPicksOpenNature() {
        // explore 0.3 → openness 0.7 (>= 0.6), regardless of the other axes.
        let p = WorldMapper.map(scores(autonomy: 0.0, explore: 0.3, expression: 0.0))
        #expect(p.archetype.usdzName == "Free_Low_Poly_Forest")
    }

    @Test func enclosedWithBelongingOrGreeneryPicksCozyCommunal() {
        // explore 0.7 → openness 0.3 (< 0.6); belonging 0.6 (>= 0.55) → cozy communal.
        let byBelonging = WorldMapper.map(scores(autonomy: 0.6, explore: 0.7, expression: 0.0))
        #expect(byBelonging.archetype.usdzName == "Cozy_living_room_baked")

        // Or via lush greenery: expression 1.0 → biophilic 1.0 (>= 0.7).
        let byGreenery = WorldMapper.map(scores(autonomy: 0.0, explore: 0.7, expression: 1.0))
        #expect(byGreenery.archetype.usdzName == "Cozy_living_room_baked")
    }

    @Test func enclosedAndSparsePicksSolitaryPath() {
        // openness < 0.6, belonging < 0.55, biophilic < 0.7 → solitary path.
        let p = WorldMapper.map(scores(autonomy: 0.2, explore: 0.7, expression: 0.0))
        #expect(p.archetype.usdzName == "FREE_Dirt_Road_Through_Forest")
    }

    // MARK: - Continuous appearance parameters (axis 4 = calm↔vivid).

    @Test func vividEndMapsToBrightWarmSaturated() {
        let p = WorldMapper.map(scores(calm: 1.0))
        #expect(abs(p.lightIntensity - 3000) < 1e-3)
        #expect(abs(p.colorTemperature - 3500) < 1e-3)
        #expect(abs(p.saturation - 1.1) < 1e-9)
    }

    @Test func calmEndMapsToDimCoolDesaturated() {
        let p = WorldMapper.map(scores(calm: 0.0))
        #expect(abs(p.lightIntensity - 500) < 1e-3)
        #expect(abs(p.colorTemperature - 7000) < 1e-3)
        #expect(abs(p.saturation - 0.5) < 1e-9)
    }

    // MARK: - Social density (axis 1) is a rounded integer in 0...8.

    @Test func socialDensityRoundsIntoZeroToEight() {
        #expect(WorldMapper.map(scores(autonomy: 0.0)).socialDensity == 0)
        #expect(WorldMapper.map(scores(autonomy: 1.0)).socialDensity == 8)
        #expect(WorldMapper.map(scores(autonomy: 0.5)).socialDensity == 4)
        #expect(WorldMapper.map(scores(autonomy: 0.4)).socialDensity == 3)  // 3.2 → 3
    }

    @Test func hopeIsPassedThroughAsFocal() {
        #expect(String(describing: WorldMapper.map(scores(hope: .explore)).focal) == "explore")
        #expect(String(describing: WorldMapper.map(scores(hope: .stable)).focal) == "stable")
    }
}

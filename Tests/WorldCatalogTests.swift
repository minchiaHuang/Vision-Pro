import Testing
@testable import VisitingArtisan

/// `WorldCatalog` maps each archetype to overlay copy, and `WorldArchetype.usdzName`
/// names the bundled USDZ. A typo here compiles fine but breaks world loading at
/// runtime — these are the cheap drift guards.
struct WorldCatalogTests {

    @Test func archetypeMapsToTheMatchingWorldId() {
        #expect(WorldCatalog.world(for: .openNature).id == "open_nature")
        #expect(WorldCatalog.world(for: .cozyCommunal).id == "calm_communal")
        #expect(WorldCatalog.world(for: .solitaryPath).id == "quiet_solitary")
    }

    @Test func everyResolvedWorldIsAKnownCatalogEntry() {
        for archetype in [WorldArchetype.openNature, .cozyCommunal, .solitaryPath] {
            let world = WorldCatalog.world(for: archetype)
            #expect(WorldCatalog.all.contains { $0.id == world.id },
                    "resolved world \(world.id) is not in WorldCatalog.all")
        }
    }

    @Test func usdzNamesMatchTheBundledAssetNames() {
        #expect(WorldArchetype.openNature.usdzName == "Free_Low_Poly_Forest")
        #expect(WorldArchetype.cozyCommunal.usdzName == "Cozy_living_room_baked")
        #expect(WorldArchetype.solitaryPath.usdzName == "FREE_Dirt_Road_Through_Forest")
    }

    @Test func catalogEntriesAndFallbackAreFullyPopulated() {
        for world in WorldCatalog.all {
            #expect(!world.id.isEmpty)
            #expect(!world.title.isEmpty)
            #expect(!world.imageName.isEmpty)
        }
        #expect(WorldCatalog.fallback.id == "fallback")
        #expect(!WorldCatalog.fallback.imageName.isEmpty)
    }
}

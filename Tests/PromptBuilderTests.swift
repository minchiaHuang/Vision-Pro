import Testing
@testable import VisitingArtisan

/// `PromptBuilder.prompt` assembles the Skybox/World-Labs text prompt from
/// `WorldParams` using low/mid/high bucketing. Pure string logic.
struct PromptBuilderTests {

    private func params(openness: Double = 0.5, social: Int = 4,
                        biophilic: Double = 0.5, saturation: Double = 0.8,
                        focal: HopeDirection = .ownPath) -> WorldParams {
        WorldParams(archetype: .openNature, lightIntensity: 1000, colorTemperature: 5500,
                    saturation: saturation, socialDensity: social, openness: openness,
                    biophilicDensity: biophilic, focal: focal)
    }

    @Test func includesArchetypeNameAndAlwaysEndsWithSuffix() {
        let p = PromptBuilder.prompt(from: params(), archetypeName: "My World")
        #expect(p.hasPrefix("A world of My World,"))
        #expect(p.hasSuffix("no human faces."))
    }

    @Test func lowOpennessSelectsTheOpenVistaPhrase() {
        let p = PromptBuilder.prompt(from: params(openness: 0.1))
        #expect(p.contains("wide open horizon"))
    }

    @Test func highOpennessSelectsTheShelteredEnclosurePhrase() {
        let p = PromptBuilder.prompt(from: params(openness: 0.9))
        #expect(p.contains("clear bounded sheltered enclosure"))
    }

    @Test func socialDensityBucketsByEighths() {
        #expect(PromptBuilder.prompt(from: params(social: 0)).contains("solitary open space"))   // 0/8 → low
        #expect(PromptBuilder.prompt(from: params(social: 8)).contains("warm gathering"))         // 8/8 → high
    }

    @Test func biophilicDensitySelectsGreeneryPhrase() {
        #expect(PromptBuilder.prompt(from: params(biophilic: 0.9)).contains("lush shared greenery"))
        #expect(PromptBuilder.prompt(from: params(biophilic: 0.1)).contains("unique landmark"))
    }

    /// axis4 bucket reads `saturation - 0.5`, so only saturation ≥ ~1.17 reaches "high".
    @Test func saturationBucketShiftsByHalf() {
        #expect(PromptBuilder.prompt(from: params(saturation: 0.5)).contains("soft desaturated cool palette")) // 0.0 → low
        #expect(PromptBuilder.prompt(from: params(saturation: 1.2)).contains("vivid saturated warm palette"))  // 0.7 → high
    }

    @Test func focalDirectionAddsItsHopePhrase() {
        #expect(PromptBuilder.prompt(from: params(focal: .people)).contains("welcoming settlement"))
        #expect(PromptBuilder.prompt(from: params(focal: .explore)).contains("new horizon yet to be explored"))
    }
}

import Testing
@testable import VisitingArtisan

/// `ConversationService.makeSystemPrompt` grounds the voice companion in THIS
/// world's hidden scores. It is a pure static builder, so it can be tested without
/// constructing the (audio-owning) service. We pin the grounding invariants.
@MainActor
struct ConversationPromptTests {

    private let world = World(id: "w", title: "A Room That Lets You Exhale",
                              imageName: "img", blurb: "Warm light.")

    private func prompt(scores: AxisScores, hopeFreeText: String = "") -> String {
        ConversationService.makeSystemPrompt(world: world, scores: scores,
                                             params: WorldMapper.map(scores),
                                             hopeFreeText: hopeFreeText)
    }

    @Test func mentionsTheWorldTitleAndSceneDescription() {
        let p = prompt(scores: .neutral)
        #expect(p.contains("A Room That Lets You Exhale"))
        #expect(p.contains("equirectangular 360 panorama"))   // PromptBuilder scene is embedded
    }

    @Test func translatesAxisLeaningsIntoPlainLanguage() {
        let autonomy = AxisScores(autonomyBelonging: 0.1, exploreStable: 0.5,
                                  expressionConnection: 0.5, calmVivid: 0.5, hope: .ownPath)
        #expect(prompt(scores: autonomy).contains("values space of their own"))

        let belonging = AxisScores(autonomyBelonging: 0.9, exploreStable: 0.5,
                                   expressionConnection: 0.5, calmVivid: 0.5, hope: .ownPath)
        #expect(prompt(scores: belonging).contains("is drawn toward closeness with others"))
    }

    @Test func describesTheHopeDirection() {
        let s = AxisScores(autonomyBelonging: 0.5, exploreStable: 0.5,
                           expressionConnection: 0.5, calmVivid: 0.5, hope: .people)
        #expect(prompt(scores: s).contains("drawing a little closer to others"))
    }

    @Test func includesFreeTextOnlyWhenProvided() {
        #expect(!prompt(scores: .neutral, hopeFreeText: "   ").contains("In their own words"))
        let withText = prompt(scores: .neutral, hopeFreeText: "I want to feel calmer")
        #expect(withText.contains("In their own words, they hope for: \"I want to feel calmer\""))
    }
}

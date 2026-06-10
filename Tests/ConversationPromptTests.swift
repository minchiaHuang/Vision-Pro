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

    /// `describeExhibitMessage` is the synthetic visitor turn sent by a wall-plaque play button.
    /// It must name THIS exhibit (caption, de-underscored stage, age) and ask the Curator for fresh
    /// words rather than a re-read of the wall label.
    @Test func describeExhibitMessageNamesTheExhibitAndAsksForFreshWording() {
        let beat = MuseumNode(stage: "return_elixir", age: 34, beat: "",
                              caption: "Curtain Call", narration: "Thirty-four. The Opera House.",
                              image_prompt: "", tone: "warm")
        let m = ConversationService.describeExhibitMessage(beat: beat)
        #expect(m.contains("Curtain Call"))            // names this exhibit
        #expect(m.contains("return elixir"))           // stage, underscores stripped
        #expect(m.contains("34"))                      // age anchor
        #expect(m.contains("say it anew"))             // asks for fresh wording, not the label
    }

    /// "Visit Old World" grounds the Curator voice in `BeatPlaqueSample.story` (no quiz/generation),
    /// so the play button there can talk about the sample exhibits. The prompt must carry the sample
    /// persona, a sample beat's narration, and the closing decision.
    @Test func curatorPromptGroundsInTheSampleStory() {
        let p = ConversationService.makeCuratorPrompt(story: BeatPlaqueSample.story,
                                                      answers: MuseumAnswers())
        #expect(p.contains(BeatPlaqueSample.story.persona))
        #expect(p.contains(BeatPlaqueSample.story.decision_prompt))
        #expect(p.contains("The Opera House"))   // the return_elixir beat's narration is embedded
    }

    /// The sample story must wrap exactly the sample beats the plaques show, so the spoken Curator
    /// and the on-wall plaques never describe different exhibits in "Visit Old World".
    @Test func sampleStoryWrapsTheSampleBeats() {
        #expect(BeatPlaqueSample.story.nodes.map(\.id) == BeatPlaqueSample.nodes.map(\.id))
        #expect(BeatPlaqueSample.story.nodes.count == 6)
        #expect(!BeatPlaqueSample.story.decision_prompt.isEmpty)
    }
}

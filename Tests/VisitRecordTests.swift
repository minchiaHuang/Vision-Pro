import Testing
import Foundation
@testable import VisitingArtisan
#if canImport(UIKit)
import UIKit
#endif

/// `VisitRecord` Codable + `VisitLibrary` index persistence (insert order, dedup, remove) and the
/// elixir-thumbnail selection. Each test uses an isolated `UserDefaults` suite, so it never touches
/// real saved visits. Mirrors `SplatLibraryTests`.
struct VisitRecordTests {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.visitlibrary.\(UUID().uuidString)")!
    }

    private func node(_ stage: String, tone: String) -> MuseumNode {
        MuseumNode(stage: stage, age: 20, beat: "", caption: "c", narration: "n",
                   image_prompt: "p", tone: tone)
    }

    private func story(_ tones: [String]) -> MuseumStory {
        MuseumStory(persona: "a dancer", cold_style: "", warm_style: "",
                    decision_prompt: "?", refusal: nil,
                    nodes: tones.enumerated().map { node("s\($0.offset)", tone: $0.element) })
    }

    private func record(_ id: String, title: String = "t") -> VisitRecord {
        VisitRecord(id: id, title: title, createdAt: Date(timeIntervalSince1970: 1000),
                    story: story(["cold", "warm"]), answers: MuseumAnswers(),
                    imageFiles: ["beat-0.png", ""], heroThumb: "thumb.jpg")
    }

    // MARK: - Codable

    @Test func visitRecordCodableRoundTrips() throws {
        let original = record("v1", title: "a world-class ballerina")
        let back = try JSONDecoder().decode(VisitRecord.self,
                                            from: JSONEncoder().encode(original))
        #expect(back.id == "v1")
        #expect(back.title == "a world-class ballerina")
        #expect(back.story.nodes.count == 2)
        #expect(back.imageFiles == ["beat-0.png", ""])
        #expect(back.heroThumb == "thumb.jpg")
    }

    @Test func museumAnswersCodableRoundTrips() throws {
        var a = MuseumAnswers()
        a.role = "a violinist"; a.city = "Sydney"; a.age = 19; a.fear = "doubt"
        let back = try JSONDecoder().decode(MuseumAnswers.self, from: JSONEncoder().encode(a))
        #expect(back.role == "a violinist")
        #expect(back.city == "Sydney")
        #expect(back.age == 19)
        #expect(back.fear == "doubt")
    }

    // MARK: - VisitLibrary index

    @Test func addInsertsNewestFirst() {
        let d = freshDefaults()
        VisitLibrary.add(record("a"), to: d)
        VisitLibrary.add(record("b"), to: d)
        #expect(VisitLibrary.load(from: d).map(\.id) == ["b", "a"])
    }

    @Test func addDeduplicatesByIdNewestWins() {
        let d = freshDefaults()
        VisitLibrary.add(record("a", title: "old"), to: d)
        VisitLibrary.add(record("b"), to: d)
        VisitLibrary.add(record("a", title: "new"), to: d)   // re-add "a"
        let saved = VisitLibrary.load(from: d)
        #expect(saved.map(\.id) == ["a", "b"])               // moved to front, no duplicate
        #expect(saved.first?.title == "new")                 // newest wins
    }

    @Test func removeDropsMatchingId() {
        let d = freshDefaults()
        VisitLibrary.add(record("a"), to: d)
        VisitLibrary.add(record("b"), to: d)
        VisitLibrary.remove(id: "a", from: d)
        #expect(VisitLibrary.load(from: d).map(\.id) == ["b"])
    }

    @Test func loadIsEmptyWithNoStoredData() {
        #expect(VisitLibrary.load(from: freshDefaults()).isEmpty)
    }

    // MARK: - Hero (elixir) thumbnail selection

    @Test func heroIndexPicksLastWarmBeat() {
        // Six beats, the two warm at the end → the elixir is the last warm one.
        #expect(VisitLibrary.heroIndex(for: story(["cold", "cold", "cold", "cold", "warm", "warm"])) == 5)
        // A single warm in the middle → that one.
        #expect(VisitLibrary.heroIndex(for: story(["cold", "warm", "cold"])) == 1)
        // No warm beat at all → falls back to the last beat.
        #expect(VisitLibrary.heroIndex(for: story(["cold", "cold"])) == 1)
    }

    // MARK: - Title fallback + shell

    @Test func titleFallsBackThroughRoleThenPersona() {
        var withRole = MuseumAnswers(); withRole.role = "a chef"
        #expect(VisitLibrary.title(answers: withRole, story: story(["cold"])) == "a chef")

        var blank = MuseumAnswers(); blank.role = "   "
        #expect(VisitLibrary.title(answers: blank, story: story(["cold"])) == "a dancer")  // persona

        let noPersona = MuseumStory(persona: "  ", cold_style: "", warm_style: "",
                                    decision_prompt: "?", refusal: nil, nodes: [])
        #expect(VisitLibrary.title(answers: blank, story: noPersona) == "Untitled visit")
    }

    @Test func makeShellHasNoImagesAndTitledByRole() {
        var a = MuseumAnswers(); a.role = "a sculptor"
        let shell = VisitLibrary.makeShell(id: "s1", story: story(["cold", "warm"]), answers: a)
        #expect(shell.id == "s1")
        #expect(shell.title == "a sculptor")
        #expect(shell.imageFiles.isEmpty)
        #expect(shell.heroThumb.isEmpty)
    }

    // MARK: - fillImages (deferred image write, in-place update)

    #if canImport(UIKit)
    private func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData()!
    }

    @Test func fillImagesWritesFilesAndPreservesShell() throws {
        let d = freshDefaults()
        let created = Date(timeIntervalSince1970: 1000)
        let shell = VisitRecord(id: "fx", title: "a pianist", createdAt: created,
                                story: story(["cold", "warm"]), answers: MuseumAnswers(),
                                imageFiles: [], heroThumb: "")
        VisitLibrary.add(shell, to: d)
        defer { VisitLibrary.remove(id: "fx", from: d) }   // also deletes the on-disk image dir

        VisitLibrary.fillImages(id: "fx", imageData: [pngData(), pngData()], from: d)

        let saved = try #require(VisitLibrary.load(from: d).first { $0.id == "fx" })
        #expect(saved.createdAt == created)                 // createdAt preserved
        #expect(saved.title == "a pianist")                 // title preserved
        #expect(saved.imageFiles == ["beat-0.png", "beat-1.png"])
        #expect(saved.heroThumb == "thumb.jpg")             // warm beat → thumbnail written
        #expect(saved.loadGalleryImages().count == 2)       // both beats decode back from disk
    }

    @Test func fillImagesIsNoOpWhenShellMissing() {
        let d = freshDefaults()
        VisitLibrary.fillImages(id: "ghost", imageData: [pngData()], from: d)   // no shell → no-op
        #expect(VisitLibrary.load(from: d).isEmpty)
    }

    // MARK: - End-to-end: AppState.saveCurrentVisit (the real production save path)

    #if DEBUG
    /// Drives the actual `AppState.saveCurrentVisit()` against a finished (stubbed) generator and an
    /// isolated `UserDefaults`: proves a card is persisted IMMEDIATELY on entry, then the same record
    /// gains its paintings + thumbnail once the (deferred) fill completes. This is the wiring the
    /// user saw "not save" — exercised deterministically, no network, no 90s wait.
    @MainActor
    @Test func saveCurrentVisitSavesShellImmediatelyThenFillsImages() async throws {
        let d = freshDefaults()
        let app = AppState()
        var answers = MuseumAnswers(); answers.role = "a cellist"
        app.museumAnswers = answers
        app.museumGenerator.installFinishedRun(story: story(["cold", "warm"]),
                                               images: [pngData(), pngData()])

        let task = app.saveCurrentVisit(into: d)

        // Phase 1 — shell persisted immediately (the card shows up before the paintings land).
        let shell = try #require(VisitLibrary.load(from: d).first)
        #expect(VisitLibrary.load(from: d).count == 1)
        #expect(shell.title == "a cellist")
        #expect(shell.imageFiles.isEmpty)

        // Phase 2 — after the deferred fill, the SAME record carries the paintings + thumbnail.
        await task?.value
        let filled = try #require(VisitLibrary.load(from: d).first { $0.id == shell.id })
        defer { VisitLibrary.remove(id: filled.id, from: d) }   // clean the on-disk image dir
        #expect(filled.imageFiles == ["beat-0.png", "beat-1.png"])
        #expect(filled.heroThumb == "thumb.jpg")
        #expect(filled.loadGalleryImages().count == 2)
    }
    #endif
    #endif
}

import Testing
import Foundation
@testable import VisitingArtisan

/// `SavedSplatWorld` Codable + `SplatLibrary` recents persistence (insert order + dedup).
/// Each test gets an isolated `UserDefaults` suite, so it never touches real recents.
struct SplatLibraryTests {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.splatlibrary.\(UUID().uuidString)")!
    }

    private func world(_ id: String, name: String = "n") -> SavedSplatWorld {
        SavedSplatWorld(id: id, name: name, createdAt: Date())
    }

    // MARK: - SavedSplatWorld

    @Test func savedSplatWorldCodableRoundTrips() throws {
        let original = SavedSplatWorld(
            id: "w1", name: "Calm Meadow", createdAt: Date(timeIntervalSince1970: 1000),
            flipUpsideDown: true, remoteURL: URL(string: "https://cdn.example/x.spz"),
            localFilename: nil)
        let back = try JSONDecoder().decode(SavedSplatWorld.self,
                                            from: JSONEncoder().encode(original))
        #expect(back.id == "w1")
        #expect(back.name == "Calm Meadow")
        #expect(back.flipUpsideDown == true)
        #expect(back.remoteURL?.absoluteString == "https://cdn.example/x.spz")
        #expect(back.localFilename == nil)
    }

    @Test func resolvedURLPrefersLocalFileThenRemote() {
        let local = SavedSplatWorld(id: "l", name: "L", createdAt: Date(), localFilename: "a.spz")
        #expect(local.resolvedURL()?.lastPathComponent == "a.spz")
        #expect(local.resolvedURL()?.path.contains("ImportedSplats") == true)

        let remote = SavedSplatWorld(id: "r", name: "R", createdAt: Date(),
                                     remoteURL: URL(string: "https://cdn.example/r.spz"))
        #expect(remote.resolvedURL()?.absoluteString == "https://cdn.example/r.spz")

        let neither = SavedSplatWorld(id: "n", name: "N", createdAt: Date())
        #expect(neither.resolvedURL() == nil)
    }

    // MARK: - SplatLibrary recents

    @Test func addInsertsNewestFirst() {
        let d = freshDefaults()
        SplatLibrary.add(world("a"), to: d)
        SplatLibrary.add(world("b"), to: d)
        #expect(SplatLibrary.load(from: d).map(\.id) == ["b", "a"])
    }

    @Test func addDeduplicatesByIdNewestWins() {
        let d = freshDefaults()
        SplatLibrary.add(world("a", name: "old"), to: d)
        SplatLibrary.add(world("b"), to: d)
        SplatLibrary.add(world("a", name: "new"), to: d)   // re-add "a"
        let saved = SplatLibrary.load(from: d)
        #expect(saved.map(\.id) == ["a", "b"])             // moved to front, no duplicate
        #expect(saved.first?.name == "new")                // newest wins
    }

    @Test func removeDropsMatchingId() {
        let d = freshDefaults()
        SplatLibrary.add(world("a"), to: d)
        SplatLibrary.add(world("b"), to: d)
        SplatLibrary.remove(id: "a", from: d)
        #expect(SplatLibrary.load(from: d).map(\.id) == ["b"])
    }

    @Test func loadIsEmptyWithNoStoredData() {
        #expect(SplatLibrary.load(from: freshDefaults()).isEmpty)
    }

    // MARK: - Seeds

    @Test func seedWorldsAreWellFormed() {
        #expect(!SplatSeeds.all.isEmpty)
        for seed in SplatSeeds.all {
            #expect(!seed.id.isEmpty)
            #expect(!seed.name.isEmpty)
        }
    }
}

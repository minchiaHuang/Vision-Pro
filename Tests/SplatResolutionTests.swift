import Testing
@testable import VisitingArtisan

/// `WorldLabsService.resolveSplatURL` picks the splat `.spz` tier by preference
/// (500k → 100k → full_res), falling back to whatever the world exposes. Pure
/// dictionary→URL logic — the heart of the splat-resolution perf feature.
@MainActor
struct SplatResolutionTests {

    private let service = WorldLabsService()

    @Test func prefersFiveHundredKWhenPresent() {
        let urls = ["100k": "https://cdn.example/a_100k.spz",
                    "500k": "https://cdn.example/b_500k.spz",
                    "full_res": "https://cdn.example/c_full.spz"]
        #expect(service.resolveSplatURL(from: urls)?.absoluteString == "https://cdn.example/b_500k.spz")
    }

    @Test func fallsBackToHundredKWhenNoFiveHundredK() {
        let urls = ["100k": "https://cdn.example/a_100k.spz",
                    "full_res": "https://cdn.example/c_full.spz"]
        #expect(service.resolveSplatURL(from: urls)?.absoluteString == "https://cdn.example/a_100k.spz")
    }

    @Test func fallsBackToFullResAsLastPreferredTier() {
        let urls = ["full_res": "https://cdn.example/c_full.spz"]
        #expect(service.resolveSplatURL(from: urls)?.absoluteString == "https://cdn.example/c_full.spz")
    }

    @Test func usesAnyAvailableTierWhenPreferenceMisses() {
        let urls = ["250k": "https://cdn.example/d_250k.spz"]
        #expect(service.resolveSplatURL(from: urls)?.absoluteString == "https://cdn.example/d_250k.spz")
    }

    @Test func nilOrEmptyDictionaryYieldsNil() {
        #expect(service.resolveSplatURL(from: nil) == nil)
        #expect(service.resolveSplatURL(from: [:]) == nil)
    }
}

import Testing
@testable import VisitingArtisan

/// `SplatSession` is the @MainActor load-progress + exit-request state machine bridging
/// the splat renderer and its controls window. Tests cover the synchronous `Phase`
/// transitions (not the time-based ramp). Serialized: shares the `.shared` singleton.
@MainActor
@Suite(.serialized)
struct SplatSessionTests {

    @Test func beginLoadingResetsToIdle() {
        let s = SplatSession.shared
        s.setReady()              // dirty it first
        s.beginLoading()
        #expect(s.phase == .idle)
        #expect(s.displayProgress == 0)
        #expect(s.exitRequested == false)
    }

    @Test func setDownloadClampsAndMapsToFortyPercentOfBar() {
        let s = SplatSession.shared
        s.beginLoading()
        s.setDownload(0.5)
        #expect(s.phase == .downloading(0.5))
        #expect(abs(s.displayProgress - 0.2) < 1e-9)   // 0.5 * 0.4
        s.setDownload(1.5)                             // clamp high → 1
        #expect(s.phase == .downloading(1.0))
        #expect(abs(s.displayProgress - 0.4) < 1e-9)
        s.setDownload(-1)                              // clamp low → 0
        #expect(s.phase == .downloading(0.0))
    }

    @Test func setReadyJumpsToFullAndReady() {
        let s = SplatSession.shared
        s.beginLoading()
        s.setReady()
        #expect(s.phase == .ready)
        #expect(s.displayProgress == 1)
    }

    @Test func setPreparingIsIgnoredOnceReady() {
        let s = SplatSession.shared
        s.beginLoading()
        s.setReady()
        s.setPreparing()          // guarded: already ready → no-op (and no ramp task)
        #expect(s.phase == .ready)
    }

    @Test func failCarriesTheMessage() {
        let s = SplatSession.shared
        s.beginLoading()
        s.fail("boom")
        #expect(s.phase == .failed("boom"))
    }

    @Test func requestExitSetsFlagAndResetClearsEverything() {
        let s = SplatSession.shared
        s.beginLoading()
        s.requestExit()
        #expect(s.exitRequested == true)
        s.reset()
        #expect(s.exitRequested == false)
        #expect(s.phase == .idle)
        #expect(s.displayProgress == 0)
    }
}

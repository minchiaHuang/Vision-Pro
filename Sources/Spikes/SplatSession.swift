import Foundation
import Observation

/// Shared, main-actor state bridging the splat immersive world's two disjoint surfaces:
/// the off-thread `SplatVisionRenderer` (which loads the `.spz` and polls the gamepad)
/// and the SwiftUI `splat-controls` window (which shows load progress and the exit
/// button). Neither can hold a reference to the other — the renderer lives inside a
/// `CompositorLayer` closure and the window is a separate scene — so they coordinate
/// through this singleton.
///
/// Two jobs:
/// 1. **Load progress**: the renderer reports coarse phases; `displayProgress` is an
///    *estimated* 0…1 the window renders as a percentage. Bundled/local `.spz` decode
///    has no fine-grained progress API, so `preparing` ramps on a time estimate; remote
///    downloads can feed a real byte fraction via `setDownload`.
/// 2. **Exit request**: both the window button and the gamepad ☰ button funnel through
///    `requestExit()`; the window observes `exitRequested` and runs the one exit path.
@MainActor
@Observable
final class SplatSession {
    static let shared = SplatSession()

    enum Phase: Equatable {
        case idle
        case downloading(Double)   // 0…1, remote real bytes (falls back to estimate)
        case preparing             // decode + chunk build (the local-file main phase)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// 0…1 for the window's ProgressView / percentage label.
    private(set) var displayProgress: Double = 0
    /// Set by the window button or the gamepad ☰ button; the window observes this and
    /// performs the single exit flow.
    var exitRequested = false

    /// Expected `preparing` duration used to ramp the estimate. A rough guess for a
    /// ~1.5M-point decode + chunk build on device; tune if it consistently over/undershoots.
    private let estimatedPrepareSeconds: Double = 3.0
    private var prepareStart: Date?
    private var rampTask: Task<Void, Never>?

    private init() {}

    // MARK: Load lifecycle (called by SplatVisionRenderer)

    /// Reset to the start of a fresh load. Call before any phase updates.
    func beginLoading() {
        rampTask?.cancel()
        rampTask = nil
        prepareStart = nil
        exitRequested = false
        displayProgress = 0
        phase = .idle
    }

    /// Remote download progress (0…1). Maps onto the first ~40% of the bar so the
    /// `preparing` decode still has room to advance afterward.
    func setDownload(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        phase = .downloading(clamped)
        displayProgress = clamped * 0.4
    }

    /// Enter the decode/build phase and start the time-based estimate ramp toward 0.95.
    func setPreparing() {
        guard phase != .ready, phase != .preparing else { return }
        phase = .preparing
        let base = displayProgress           // continue from wherever download left off
        prepareStart = Date()
        rampTask?.cancel()
        rampTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let start = self.prepareStart else { return }
                let elapsed = Date().timeIntervalSince(start)
                let frac = min(elapsed / self.estimatedPrepareSeconds, 1)
                // Ease toward 0.95 so it never visually "completes" before ready.
                self.displayProgress = max(self.displayProgress, base + (0.95 - base) * frac)
                if self.phase != .preparing { return }
                try? await Task.sleep(nanoseconds: 100_000_000) // ~0.1s
            }
        }
    }

    /// Scene published — jump to 100% and stop the ramp.
    func setReady() {
        rampTask?.cancel()
        rampTask = nil
        displayProgress = 1
        phase = .ready
    }

    func fail(_ message: String) {
        rampTask?.cancel()
        rampTask = nil
        phase = .failed(message)
    }

    // MARK: Exit

    /// Request leaving the world. Idempotent; the window's `onChange` runs the actual
    /// `dismissImmersiveSpace` flow.
    func requestExit() {
        exitRequested = true
    }

    /// Clear everything once the window has finished exiting.
    func reset() {
        rampTask?.cancel()
        rampTask = nil
        prepareStart = nil
        exitRequested = false
        displayProgress = 0
        phase = .idle
    }
}

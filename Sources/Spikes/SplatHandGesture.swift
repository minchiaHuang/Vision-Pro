#if os(visionOS)
import Foundation
import ARKit
import simd
import os

// MARK: - Processor (NOT thread-safe; call from the ARKit anchor-update task only)

/// Detects a TWO-HAND pinch gesture and emits per-update (yaw, scale) deltas for the
/// in-world USDZ model — Quick-Look style "hold and turn / pull apart to grow". State for
/// both hands is kept here so the gesture is evaluated whenever either hand updates.
///
/// Only the two-hand gesture is supported (no single-hand translate): rotation and scale
/// are both about the model's own centre / vertical axis, which is invariant to the
/// player's locomotion yaw, so no world↔player space correction is needed.
///
/// Not thread-safe: call exclusively from the `HandTrackingProvider.anchorUpdates` loop.
final class SplatHandGestureProcessor {
    /// Distance to BEGIN a pinch (thumb ↔ index). Hysteresis with `pinchOpen`.
    private let pinchClose: Float = 0.025   // 2.5 cm
    /// Distance to END a pinch.
    private let pinchOpen:  Float = 0.040   // 4.0 cm
    /// Below this inter-hand span the span/angle are too noisy to trust.
    private let minSpan: Float = 0.05       // 5 cm

    private var leftPinching  = false
    private var rightPinching = false
    /// Current pinch midpoint per hand (nil when that hand is not pinching).
    private var leftMid:  SIMD3<Float>?
    private var rightMid: SIMD3<Float>?
    /// Reference span/angle of the two-hand gesture from the previous evaluation.
    private var prevSpan:  Float?
    private var prevAngle: Float?

    /// Feed each `HandAnchor` update here. Returns the `(yaw, scaleMul)` delta to apply
    /// this update, or nil if the two-hand gesture isn't active / nothing changed.
    /// `scaleMul` is multiplicative (1.0 = no change); `yaw` is radians about +Y.
    func process(anchor: HandAnchor) -> (yaw: Float, scaleMul: Float)? {
        // ARKit adapter: pull this hand's thumb/index tips into world space, then defer to
        // the pure core. nil positions = not tracked (the core clears that hand's state).
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            return update(chirality: anchor.chirality, thumbTip: nil, indexTip: nil)
        }
        let thumb = worldPos(skeleton.joint(.thumbTip), anchor: anchor)
        let index = worldPos(skeleton.joint(.indexFingerTip), anchor: anchor)
        return update(chirality: anchor.chirality, thumbTip: thumb, indexTip: index)
    }

    /// Pure gesture core: takes one hand's thumb/index world positions (nil = not tracked)
    /// and returns the two-hand `(yaw, scaleMul)` delta, or nil. No ARKit anchor, so this is
    /// exercisable with synthetic input in the Simulator (see `SplatHandGestureSelfTest`).
    func update(chirality: HandAnchor.Chirality,
                thumbTip: SIMD3<Float>?,
                indexTip: SIMD3<Float>?) -> (yaw: Float, scaleMul: Float)? {
        updatePinch(chirality: chirality, thumbTip: thumbTip, indexTip: indexTip)

        // Two-hand gesture requires both hands pinching with a usable separation.
        guard let lhs = leftMid, let rhs = rightMid else {
            prevSpan = nil; prevAngle = nil
            return nil
        }
        let span = simd_distance(lhs, rhs)
        guard span >= minSpan else {
            prevSpan = nil; prevAngle = nil
            return nil
        }
        // Angle of the inter-hand vector in the horizontal (XZ) plane.
        let angle = atan2(rhs.z - lhs.z, rhs.x - lhs.x)

        defer { prevSpan = span; prevAngle = angle }

        // First frame of the gesture: seed the reference, emit nothing.
        guard let pSpan = prevSpan, let pAngle = prevAngle else { return nil }

        let scaleMul: Float = pSpan > 0.001 ? span / pSpan : 1.0
        let yaw = shortestAngleDelta(from: pAngle, to: angle)
        return (yaw, scaleMul)
    }

    /// Updates one hand's pinch state + midpoint (hysteresis) from its thumb/index tips.
    /// nil positions (untracked) clear that hand.
    private func updatePinch(chirality: HandAnchor.Chirality,
                             thumbTip: SIMD3<Float>?, indexTip: SIMD3<Float>?) {
        guard let thumb = thumbTip, let index = indexTip else {
            setHand(chirality, pinching: false, midpoint: nil)
            return
        }
        let distance = simd_distance(thumb, index)

        var pinching = chirality == .left ? leftPinching : rightPinching
        if  pinching && distance > pinchOpen  { pinching = false }
        if !pinching && distance < pinchClose { pinching = true  }

        setHand(chirality,
                pinching: pinching,
                midpoint: pinching ? (thumb + index) * 0.5 : nil)
    }

    private func setHand(_ chirality: HandAnchor.Chirality, pinching: Bool, midpoint: SIMD3<Float>?) {
        switch chirality {
        case .left:  leftPinching  = pinching; leftMid  = midpoint
        case .right: rightPinching = pinching; rightMid = midpoint
        @unknown default: break
        }
    }

    /// World-space position of a hand skeleton joint.
    private func worldPos(_ joint: HandSkeleton.Joint, anchor: HandAnchor) -> SIMD3<Float> {
        let t = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
        return SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    /// Wraps the raw angle difference into (−π, π] so a gesture crossing ±π doesn't spin.
    private func shortestAngleDelta(from a: Float, to b: Float) -> Float {
        var d = b - a
        while d >  .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

// MARK: - Manipulation sink (thread-safe bridge: gesture task / debug UI → render thread)

/// Accumulates model-manipulation deltas and lets the render thread consume them atomically
/// once per frame. Fed by the hand-tracking task (device) and the on-screen debug pad
/// (Simulator). Mirrors `SplatManualInput`: zero-delta = inert, so it's always safe to read.
final class SplatModelManipulation: @unchecked Sendable {
    static let shared = SplatModelManipulation()
    private init() {}

    private let lock = NSLock()
    private var yaw: Float = 0
    private var scaleMul: Float = 1
    private var dirty = false

    /// Add a rotation (radians, about +Y) and a multiplicative scale step.
    func add(yaw dy: Float, scaleMul ds: Float) {
        lock.lock()
        yaw      += dy
        scaleMul *= ds
        dirty     = true
        lock.unlock()
    }

    /// Returns and resets the accumulated delta; nil when nothing changed this frame.
    func consume() -> (yaw: Float, scaleMul: Float)? {
        lock.lock(); defer { lock.unlock() }
        guard dirty else { return nil }
        let result = (yaw, scaleMul)
        yaw = 0; scaleMul = 1; dirty = false
        return result
    }

    /// Drops any pending delta (e.g. when leaving a world), so the next world starts clean.
    func reset() {
        lock.lock(); yaw = 0; scaleMul = 1; dirty = false; lock.unlock()
    }
}

#if DEBUG
// MARK: - Self-test (Simulator-runnable; no device / no hand tracking needed)

/// Feeds SYNTHETIC thumb/index positions through `SplatHandGestureProcessor.update(...)` to
/// verify the gesture algorithm (pinch hysteresis, two-hand scale/yaw, ±π wrap, tracking
/// loss) WITHOUT a Vision Pro — the one tier of Phase 2 the Simulator can't otherwise reach
/// (the on-screen pad only exercises the render maths; real ARKit hand data needs a device).
/// Triggered once from the dev menu; results go to os_log (category "HandGesture").
enum SplatHandGestureSelfTest {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VisitingArtisan",
                                    category: "HandGesture")
    private static var hasRun = false

    /// Thumb/index tips `gap` metres apart, centred on `mid` (so the pinch midpoint == mid).
    private static func tips(at mid: SIMD3<Float>, gap: Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let h = SIMD3<Float>(gap * 0.5, 0, 0)
        return (mid + h, mid - h) // (thumb, index): |thumb − index| == gap
    }

    private static func approx(_ a: Float, _ b: Float, _ tol: Float = 1e-3) -> Bool { abs(a - b) < tol }

    static func run() {
        guard !hasRun else { return }
        hasRun = true

        var passed = 0, total = 0
        func check(_ name: String, _ cond: Bool) {
            total += 1
            if cond { passed += 1; log.notice("SELFTEST PASS: \(name, privacy: .public)") }
            else    { log.error("SELFTEST FAIL: \(name, privacy: .public)") }
        }
        // Pinched (gap < pinchClose 2.5cm) vs open (gap > pinchOpen 4cm).
        let pinch: Float = 0.01

        // 1 · Single-hand pinch → no two-hand output.
        do {
            let p = SplatHandGestureProcessor()
            let (t, i) = tips(at: [-0.15, 1, -0.5], gap: pinch)
            check("single-hand pinch → nil", p.update(chirality: .left, thumbTip: t, indexTip: i) == nil)
        }

        // 2 · Two hands pinched and still → seed (nil), then ~identity (yaw 0, scale 1).
        do {
            let p = SplatHandGestureProcessor()
            let L = SIMD3<Float>(-0.15, 1, -0.5), R = SIMD3<Float>(0.15, 1, -0.5)
            feed(p, .left, at: L, gap: pinch)
            _ = feed(p, .right, at: R, gap: pinch)            // seeds
            let out = feed(p, .right, at: R, gap: pinch)      // steady
            check("two-hand steady → ~identity",
                  out != nil && approx(out!.yaw, 0) && approx(out!.scaleMul, 1))
        }

        // 3 · Move one hand to widen / narrow the span → scaleMul >1 / <1 (left fixed).
        do {
            let p = SplatHandGestureProcessor(); let L = SIMD3<Float>(0, 1, -0.5)
            feed(p, .left, at: L, gap: pinch)
            _ = feed(p, .right, at: L + [0.3, 0, 0], gap: pinch)         // seed span 0.30
            let out = feed(p, .right, at: L + [0.4, 0, 0], gap: pinch)   // span 0.40
            check("pull apart → scaleMul > 1", out != nil && approx(out!.scaleMul, 0.4 / 0.3))
        }
        do {
            let p = SplatHandGestureProcessor(); let L = SIMD3<Float>(0, 1, -0.5)
            feed(p, .left, at: L, gap: pinch)
            _ = feed(p, .right, at: L + [0.3, 0, 0], gap: pinch)         // seed span 0.30
            let out = feed(p, .right, at: L + [0.2, 0, 0], gap: pinch)   // span 0.20
            check("bring together → scaleMul < 1", out != nil && approx(out!.scaleMul, 0.2 / 0.3))
        }

        // 4 · Rotate the right hand about the fixed left by θ → yaw ≈ θ, scale ≈ 1.
        do {
            let p = SplatHandGestureProcessor(); let L = SIMD3<Float>(0, 1, -0.5)
            let theta: Float = 0.5
            feed(p, .left, at: L, gap: pinch)
            _ = feed(p, .right, at: L + [0.3, 0, 0], gap: pinch)         // seed angle 0
            let r = L + [0.3 * cos(theta), 0, 0.3 * sin(theta)]
            let out = feed(p, .right, at: r, gap: pinch)
            check("rotate +θ → yaw ≈ θ", out != nil && approx(out!.yaw, theta) && approx(out!.scaleMul, 1))
        }

        // 5 · Inter-hand angle crosses ±π → wrapped to a small yaw, NOT a ~2π spin.
        do {
            let p = SplatHandGestureProcessor(); let L = SIMD3<Float>(0, 1, -0.5)
            feed(p, .left, at: L, gap: pinch)
            _ = feed(p, .right, at: L + [-0.3, 0,  0.001], gap: pinch)   // angle ≈ +π
            let out = feed(p, .right, at: L + [-0.3, 0, -0.001], gap: pinch) // angle ≈ −π
            check("angle wrap ±π → small yaw", out != nil && abs(out!.yaw) < 0.05)
        }

        // 6 · Hysteresis: open at 3cm, pinch at 2cm, hold at 3.5cm, release at 4.5cm
        //     (left held pinched; only the right hand's gap varies, its midpoint fixed).
        do {
            let p = SplatHandGestureProcessor()
            let L = SIMD3<Float>(0, 1, -0.5), Rm = SIMD3<Float>(0.3, 1, -0.5)
            feed(p, .left, at: L, gap: pinch)
            check("hysteresis: 3cm stays open → nil",  feed(p, .right, at: Rm, gap: 0.03) == nil)
            _ = feed(p, .right, at: Rm, gap: 0.02)                       // pinches, seeds
            check("hysteresis: 2cm pinches → non-nil", feed(p, .right, at: Rm, gap: 0.02) != nil)
            check("hysteresis: 3.5cm holds → non-nil", feed(p, .right, at: Rm, gap: 0.035) != nil)
            check("hysteresis: 4.5cm releases → nil",  feed(p, .right, at: Rm, gap: 0.045) == nil)
        }

        // 7 · Tracking loss mid-gesture → re-seeds on resume (no spurious delta).
        do {
            let p = SplatHandGestureProcessor(); let L = SIMD3<Float>(0, 1, -0.5)
            feed(p, .left, at: L, gap: pinch)
            _ = feed(p, .right, at: L + [0.3, 0, 0], gap: pinch)         // seed
            _ = feed(p, .right, at: L + [0.4, 0, 0], gap: pinch)         // active gesture
            _ = p.update(chirality: .right, thumbTip: nil, indexTip: nil) // right lost
            let resume = feed(p, .right, at: L + [0.25, 0, 0], gap: pinch) // re-acquire
            check("tracking loss → re-seed (nil)", resume == nil)
        }

        log.notice("SELFTEST: \(passed, privacy: .public)/\(total, privacy: .public) passed")
    }

    @discardableResult
    private static func feed(_ p: SplatHandGestureProcessor, _ c: HandAnchor.Chirality,
                             at mid: SIMD3<Float>, gap: Float) -> (yaw: Float, scaleMul: Float)? {
        let (t, i) = tips(at: mid, gap: gap)
        return p.update(chirality: c, thumbTip: t, indexTip: i)
    }
}
#endif // DEBUG

#endif // os(visionOS)

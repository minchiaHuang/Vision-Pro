#if os(visionOS)
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
        updatePinch(for: anchor)

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

    /// Updates one hand's pinch state + midpoint (hysteresis), reading thumb/index tips.
    private func updatePinch(for anchor: HandAnchor) {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            setHand(anchor.chirality, pinching: false, midpoint: nil)
            return
        }
        let thumb = worldPos(skeleton.joint(.thumbTip), anchor: anchor)
        let index = worldPos(skeleton.joint(.indexFingerTip), anchor: anchor)
        let distance = simd_distance(thumb, index)

        var pinching = anchor.chirality == .left ? leftPinching : rightPinching
        if  pinching && distance > pinchOpen  { pinching = false }
        if !pinching && distance < pinchClose { pinching = true  }

        setHand(anchor.chirality,
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

#endif // os(visionOS)

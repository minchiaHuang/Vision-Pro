#if !os(visionOS)
import Foundation
import Observation
import CoreMotion
import simd

/// Wraps CoreMotion device-motion so the 360 view can follow the device's
/// physical orientation. Exposes a `simd_quatf` the RealityView reads each frame.
/// Note: the gyroscope is unavailable in the iOS Simulator — test on a device.
@MainActor
@Observable
final class MotionManager {

    /// Sphere orientation derived from device attitude (relative to the recenter reference).
    private(set) var orientation = simd_quatf(angle: 0, axis: [0, 1, 0])

    /// Whether device motion is available on this hardware.
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    private let manager = CMMotionManager()
    private var referenceAttitude: CMAttitude?

    // Axis sign correction from the CoreMotion-derived rotation to the inward
    // (scale.x = -1, mirrored) sphere. Start from the inverse, then flip axes.
    // pitch = vertical (X), yaw = horizontal (Y), roll (Z). Tuned on device:
    // flipping Y & Z together is the valid "mirror across X" that reverses the
    // horizontal sense while keeping vertical. Flip a constant if an axis is off.
    private let signX: Float = 1     // pitch (vertical) — keep
    private let signY: Float = -1    // yaw (horizontal) — reversed to fix inversion
    private let signZ: Float = -1    // roll — paired with yaw

    // The app is locked to landscape, but CoreMotion attitude is reported in the
    // device's portrait-relative frame. Pre-rotate about the viewing axis (Z) to
    // realign horizontal/vertical for landscape. Tune this angle on device
    // (try ±90°) together with the sign knobs above.
    private let landscapeFixRadians: Float = -.pi / 2

    init() {
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        referenceAttitude = nil
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.update(from: motion.attitude)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    /// Treat the current device attitude as "straight ahead".
    func recenter() {
        if let current = manager.deviceMotion?.attitude.copy() as? CMAttitude {
            referenceAttitude = current
        } else {
            referenceAttitude = nil
        }
    }

    // MARK: - Mapping

    private func update(from attitude: CMAttitude) {
        // Capture the first sample as the reference so we start looking forward.
        if referenceAttitude == nil {
            referenceAttitude = attitude.copy() as? CMAttitude
        }
        if let reference = referenceAttitude {
            attitude.multiply(byInverseOf: reference)
        }

        // CoreMotion quaternion (w, x, y, z) of the device relative to reference.
        let q = attitude.quaternion
        let device = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))

        // The camera sits at the sphere center; rotating the sphere by the inverse of
        // the device rotation makes the panorama appear fixed in world space.
        // Apply per-axis sign correction for the mirrored sphere / frame mismatch.
        let inv = device.inverse
        let signed = simd_quatf(ix: signX * inv.imag.x,
                                iy: signY * inv.imag.y,
                                iz: signZ * inv.imag.z,
                                r: inv.real)

        // Pre-rotate about the viewing axis to realign for landscape hold.
        let landscapeFix = simd_quatf(angle: landscapeFixRadians, axis: [0, 0, 1])
        orientation = landscapeFix * signed
    }
}
#endif

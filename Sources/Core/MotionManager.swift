#if !os(visionOS)
import Foundation
import Observation
import CoreMotion
import UIKit
import simd

/// Wraps CoreMotion device-motion so the 360 view can follow the device's
/// physical orientation.
///
/// ## Why the change-of-basis matters
/// `CMAttitude` is always reported in the device-natural **portrait** frame
/// (X along the short edge, Y along the long edge, Z out of the screen) —
/// regardless of the interface orientation. Our app is landscape-only, so the
/// view's horizontal axis = device Y and vertical axis = device X. Without
/// remapping, tilting the iPad's top edge forward would rotate the panorama
/// horizontally (yaw) instead of vertically (pitch).
///
/// We fix this by computing `Q_view_from_device` for the active landscape
/// orientation and applying it as a quaternion **similarity transform** to
/// the attitude before inverting it for the inward-facing sphere:
///
///     attitudeInView = Q_v ⊗ attitudeDevice ⊗ Q_v⁻¹
///
/// References:
/// - https://developer.apple.com/documentation/coremotion/cmattitude
/// - https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe
/// - https://iosdeveloperzone.com/2016/05/02/using-scenekit-and-coremotion-in-swift/
///
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

    // Mirror compensation for the inward-facing sphere (entity.scale.x = -1).
    // After the device→view change-of-basis, inv.imag.x drives the view's pitch
    // (vertical) and inv.imag.y drives the yaw (horizontal). Tuned on device:
    // both pitch and yaw needed flipping for the mirrored sphere; roll stays.
    private let signX: Float = -1    // pitch (vertical)   — flipped
    private let signY: Float = -1    // yaw   (horizontal) — flipped
    private let signZ: Float =  1    // roll

    /// Quaternion that maps the device-portrait frame to the view-landscape frame.
    /// Recomputed whenever the interface orientation changes.
    private var viewFromDevice = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])

    private var orientationObserver: NSObjectProtocol?

    init() {
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    // No deinit cleanup of the observer token — `stop()` covers the normal
    // lifecycle (called on Gyro toggle / view disappear). The observer closure
    // uses `[weak self]`, so a leaked registration past dealloc is a no-op.

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        referenceAttitude = nil
        updateViewFromDeviceForCurrentInterfaceOrientation()
        startObservingOrientationChanges()
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.update(from: motion.attitude)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        stopObservingOrientationChanges()
    }

    /// Treat the current device attitude as "straight ahead".
    func recenter() {
        if let current = manager.deviceMotion?.attitude.copy() as? CMAttitude {
            referenceAttitude = current
        } else {
            referenceAttitude = nil
        }
    }

    // MARK: - Orientation handling

    private func startObservingOrientationChanges() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateViewFromDeviceForCurrentInterfaceOrientation()
                // Re-anchor so the user's current physical pose is "forward" in the new frame.
                self.recenter()
            }
        }
    }

    private func stopObservingOrientationChanges() {
        if let token = orientationObserver {
            NotificationCenter.default.removeObserver(token)
            orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func updateViewFromDeviceForCurrentInterfaceOrientation() {
        // Read the live UI orientation from the active window scene; UIDevice.orientation
        // can return .faceUp/.faceDown which don't help us pick landscape direction.
        // iOS 26 deprecated UIWindowScene.interfaceOrientation in favour of effectiveGeometry.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let interface: UIInterfaceOrientation
        if let scene {
            if #available(iOS 26.0, *) {
                interface = scene.effectiveGeometry.interfaceOrientation
            } else {
                interface = scene.interfaceOrientation
            }
        } else {
            interface = .landscapeRight
        }

        // Rotation about the screen-normal (Z) that takes portrait axes → landscape view axes.
        let angle: Float
        switch interface {
        case .landscapeLeft:      angle = .pi / 2     // home / USB-C on the left
        case .landscapeRight:     angle = -.pi / 2    // home / USB-C on the right
        case .portraitUpsideDown: angle = .pi
        default:                  angle = 0           // .portrait or .unknown
        }
        viewFromDevice = simd_quatf(angle: angle, axis: [0, 0, 1])
    }

    // MARK: - Mapping

    private func update(from attitude: CMAttitude) {
        // Anchor the first sample as "forward" so the user starts looking ahead.
        if referenceAttitude == nil {
            referenceAttitude = attitude.copy() as? CMAttitude
        }
        if let reference = referenceAttitude {
            attitude.multiply(byInverseOf: reference)
        }

        // Attitude in device-portrait frame, as a simd quaternion.
        let q = attitude.quaternion
        let device = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))

        // Change of basis: express the same rotation in the landscape view frame.
        let deviceInView = viewFromDevice * device * viewFromDevice.inverse

        // Inward sphere rotates opposite to the camera's intended look direction.
        let inv = deviceInView.inverse

        // Mirror compensation for entity.scale.x = -1 (inward-facing sphere).
        let signed = simd_quatf(ix: signX * inv.imag.x,
                                iy: signY * inv.imag.y,
                                iz: signZ * inv.imag.z,
                                r: inv.real)

        orientation = signed
    }
}
#endif

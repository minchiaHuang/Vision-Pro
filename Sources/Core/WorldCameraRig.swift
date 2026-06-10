import RealityKit
import GameController

/// Holds the first-person camera state and applies it to the RealityKit camera
/// each frame. Both touch gestures and the extended gamepad (PS5 / Switch Pro /
/// Xbox) mutate this
/// same rig, so they coexist without fighting over SwiftUI state.
@MainActor
final class WorldCameraRig {
    var yaw: Float = 0
    var pitch: Float = 0
    var position: SIMD3<Float> = .zero
    /// Largest dimension of the loaded scene; movement/look speed scale by it.
    var span: Float = 1

    weak var camera: PerspectiveCamera?
    var updateSubscription: EventSubscription?

    private var initialPosition: SIMD3<Float> = .zero
    private var initialYaw: Float = 0
    private var initialPitch: Float = 0
    private var resetWasPressed = false

    private let lookSpeed: Float = 2.4          // rad/sec at full stick deflection
    private let moveFraction: Float = 0.06      // scene spans/sec at full deflection
    private let deadzone: Float = 0.1

    /// Yaw-only basis so left-stick / pinch movement stays on the horizontal
    /// plane (vertical is reserved for the triggers).
    private var moveForward: SIMD3<Float> {
        simd_quatf(angle: yaw, axis: [0, 1, 0]).act([0, 0, -1])
    }
    private var moveRight: SIMD3<Float> {
        simd_quatf(angle: yaw, axis: [0, 1, 0]).act([1, 0, 0])
    }

    func configure(camera: PerspectiveCamera, position: SIMD3<Float>, span: Float) {
        self.camera = camera
        self.position = position
        self.span = span
        self.yaw = 0
        self.pitch = 0
        initialPosition = position
        initialYaw = 0
        initialPitch = 0
    }

    /// Camera-less setup for renderers that consume a view matrix directly (e.g. the
    /// MetalSplatter splat path) instead of a RealityKit `PerspectiveCamera`.
    func configure(position: SIMD3<Float>, span: Float) {
        self.camera = nil
        self.position = position
        self.span = span
        self.yaw = 0
        self.pitch = 0
        initialPosition = position
        initialYaw = 0
        initialPitch = 0
    }

    func apply() {
        camera?.position = position
        camera?.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// World→view matrix for the splat renderer: the inverse of the camera's world
    /// transform `T(position) · R(yaw,pitch)`. Same orientation convention as `apply()`.
    func viewMatrix() -> simd_float4x4 {
        let r = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        var world = matrix_float4x4(r)
        world.columns.3 = SIMD4(position, 1)
        return simd_inverse(world)
    }

    /// Integrates one frame of gamepad input. No-op (apply still runs) when no
    /// controller is connected, leaving touch gestures in control.
    func tick(deltaTime dt: Float, gamepad gp: GCExtendedGamepad?) {
        guard let gp else { return }

        // Right stick → look.
        yaw -= dead(gp.rightThumbstick.xAxis.value) * lookSpeed * dt
        pitch = clampPitch(pitch + dead(gp.rightThumbstick.yAxis.value) * lookSpeed * dt)

        // Left stick → move on the horizontal plane.
        let speed = span * moveFraction * dt
        position += moveForward * (dead(gp.leftThumbstick.yAxis.value) * speed)
        position += moveRight * (dead(gp.leftThumbstick.xAxis.value) * speed)

        // Triggers → vertical (right up, left down, analog).
        position.y += (gp.rightTrigger.value - gp.leftTrigger.value) * speed

        // Right/bottom face button (A or B) → reset, edge-triggered. Accepting both
        // sidesteps the Switch Pro A/B position swap (Apple's mapping is inconsistent).
        let pressed = gp.buttonB.isPressed || gp.buttonA.isPressed
        if pressed && !resetWasPressed { resetToInitial() }
        resetWasPressed = pressed
    }

    func resetToInitial() {
        position = initialPosition
        yaw = initialYaw
        pitch = initialPitch
    }

    // Gesture deltas feed straight into the rig.
    func look(deltaX: Float, deltaY: Float) {
        yaw -= deltaX * 0.005
        pitch = clampPitch(pitch + deltaY * 0.005)
    }
    func dolly(delta: Float) {
        position += moveForward * (delta * span * 0.5)
    }

    private func dead(_ v: Float) -> Float { abs(v) < deadzone ? 0 : v }
    private func clampPitch(_ p: Float) -> Float { min(max(p, -.pi * 0.49), .pi * 0.49) }
}

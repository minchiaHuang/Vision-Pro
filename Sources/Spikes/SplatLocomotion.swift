import simd
import GameController

/// Artificial locomotion for the walkable splat world, shared by the platforms that
/// drive a view matrix directly. A plain value type (no actor isolation) so the
/// visionOS CompositorServices render loop can own and mutate it on its render thread.
///
/// Movement model mirrors the proven iOS `WorldCameraRig`: left stick moves on the
/// horizontal plane, right stick X turns (yaw), triggers move vertically. Pitch is
/// intentionally NOT applied here on visionOS — the user's head supplies pitch via
/// head tracking, and tilting the whole world is uncomfortable.
struct SplatLocomotion {
    var yaw: Float = 0
    var position: SIMD3<Float> = .zero
    /// Largest scene dimension; movement speed scales by it.
    var span: Float = 1

    private var initialPosition: SIMD3<Float> = .zero
    private var initialYaw: Float = 0
    private var resetWasPressed = false

    private let lookSpeed: Float = 2.4     // rad/sec at full stick deflection
    private let moveFraction: Float = 0.6  // scene spans/sec at full deflection
    private let deadzone: Float = 0.1

    init(position: SIMD3<Float> = .zero, span: Float = 1) {
        self.position = position
        self.span = span
        self.initialPosition = position
        self.initialYaw = 0
    }

    /// Yaw-only horizontal basis so movement stays on the ground plane.
    private var forward: SIMD3<Float> { simd_quatf(angle: yaw, axis: [0, 1, 0]).act([0, 0, -1]) }
    private var right: SIMD3<Float> { simd_quatf(angle: yaw, axis: [0, 1, 0]).act([1, 0, 0]) }

    /// Integrates one frame of gamepad input. No-op when no controller is connected.
    mutating func tick(deltaTime dt: Float, gamepad gp: GCExtendedGamepad?) {
        guard let gp else { return }

        // Right stick X → turn (yaw). Pitch deliberately left to head tracking.
        yaw -= dead(gp.rightThumbstick.xAxis.value) * lookSpeed * dt

        // Left stick → move on the horizontal plane.
        let speed = span * moveFraction * dt
        position += forward * (dead(gp.leftThumbstick.yAxis.value) * speed)
        position += right * (dead(gp.leftThumbstick.xAxis.value) * speed)

        // Triggers → vertical (R2 up, L2 down, analog).
        position.y += (gp.rightTrigger.value - gp.leftTrigger.value) * speed

        // ○ (buttonB) → reset to the start viewpoint, edge-triggered.
        let pressed = gp.buttonB.isPressed
        if pressed && !resetWasPressed {
            position = initialPosition
            yaw = initialYaw
        }
        resetWasPressed = pressed
    }

    /// The player "vehicle" world transform (yaw + position) that places the user's
    /// tracked head inside the scene. Compose as `playerTransform · deviceAnchor · eyeTransform`.
    func playerTransform() -> simd_float4x4 {
        var m = matrix_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        m.columns.3 = SIMD4(position, 1)
        return m
    }

    private func dead(_ v: Float) -> Float { abs(v) < deadzone ? 0 : v }
}

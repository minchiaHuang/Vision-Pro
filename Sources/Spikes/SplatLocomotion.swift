import simd
import Foundation
import GameController

/// Thread-safe locomotion fallback for when no game controller is connected (notably
/// the visionOS Simulator). On-screen hold-to-move controls write here on the main
/// actor; `SplatVisionRenderer` reads a `snapshot()` each frame on its render thread.
/// Zero values = no influence, so this is inert whenever the user isn't touching it.
final class SplatManualInput: @unchecked Sendable {
    static let shared = SplatManualInput()

    struct Snapshot { var forward: Float = 0; var turn: Float = 0 }

    private let lock = NSLock()
    private var state = Snapshot()

    /// `forward` +1 walks forward / −1 back; `turn` +1 turns right / −1 left.
    func set(forward: Float, turn: Float) {
        lock.lock(); state = Snapshot(forward: forward, turn: turn); lock.unlock()
    }
    func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return state }
    func reset() { lock.lock(); state = Snapshot(); lock.unlock() }

    private init() {}
}

/// Artificial locomotion for the walkable splat world, shared by the platforms that
/// drive a view matrix directly. A plain value type (no actor isolation) so the
/// visionOS CompositorServices render loop can own and mutate it on its render thread.
///
/// Movement model mirrors the proven iOS `WorldCameraRig`: left stick moves on the
/// horizontal plane, right stick X turns (yaw), triggers move vertically. Pitch is
/// intentionally NOT applied here on visionOS — the user's head supplies pitch via
/// head tracking, and tilting the whole world is uncomfortable.
struct SplatLocomotion {
    /// Axis-aligned hard walls in player space.
    struct Box { var min: SIMD3<Float>; var max: SIMD3<Float> }

    var yaw: Float = 0
    var position: SIMD3<Float> = .zero
    /// Largest scene dimension; movement speed scales by it.
    var span: Float = 1
    /// Optional hard boundary (player-space, already margin-inset). When set, `tick`
    /// clamps `position` into this box every frame — a wall the user can't walk through.
    /// `nil` = unbounded; the splat `.spz` path leaves it nil to keep free movement.
    var boundary: Box? = nil
    /// When true, input never changes the player's Y — the triggers' vertical fly is ignored. The
    /// parametric walk-in worlds set this for a first-person locked eye height (Y is then driven
    /// externally from the head pose); the free-flying splat `.spz` path leaves it false.
    var lockVertical: Bool = false

    private var initialPosition: SIMD3<Float> = .zero
    private var initialYaw: Float = 0
    private var resetWasPressed = false

    private let lookSpeed: Float = 2.4     // rad/sec at full stick deflection
    private let moveFraction: Float = 0.06  // scene spans/sec at full deflection
    private let deadzone: Float = 0.1

    init(position: SIMD3<Float> = .zero, yaw: Float = 0, span: Float = 1) {
        self.position = position
        self.yaw = yaw
        self.span = span
        self.initialPosition = position
        self.initialYaw = yaw
    }

    /// Yaw-only horizontal basis so movement stays on the ground plane.
    private var forward: SIMD3<Float> { simd_quatf(angle: yaw, axis: [0, 1, 0]).act([0, 0, -1]) }
    private var right: SIMD3<Float> { simd_quatf(angle: yaw, axis: [0, 1, 0]).act([1, 0, 0]) }

    /// Integrates one frame of input. Combines the game controller (if any) with the
    /// on-screen `manual` fallback so the world stays walkable without a controller
    /// (e.g. in the Simulator). No controller + no manual input = no movement.
    mutating func tick(deltaTime dt: Float, gamepad gp: GCExtendedGamepad?,
                       manual: SplatManualInput.Snapshot = .init()) {
        var turnX: Float = 0   // +right
        var moveX: Float = 0   // strafe (+right)
        var moveY: Float = 0   // +forward
        var lift: Float = 0    // +up

        if let gp {
            turnX += dead(gp.rightThumbstick.xAxis.value)
            moveX += dead(gp.leftThumbstick.xAxis.value)
            moveY += dead(gp.leftThumbstick.yAxis.value)
            // Triggers → vertical (right up, left down, analog).
            lift  += gp.rightTrigger.value - gp.leftTrigger.value
        }
        // `manual` is the no-controller fallback (on-screen pad), supplied by the caller;
        // zero when untouched.
        turnX += manual.turn
        moveY += manual.forward

        // Right stick X / turn buttons → yaw. Pitch deliberately left to head tracking.
        yaw -= turnX * lookSpeed * dt

        // Move on the horizontal plane; triggers add vertical.
        let speed = span * moveFraction * dt
        position += forward * (moveY * speed)
        position += right * (moveX * speed)
        if !lockVertical { position.y += lift * speed }

        // Right/bottom face button (A or B) → reset to the start viewpoint, edge-triggered
        // (controller only). Accepting both sidesteps the Switch Pro A/B position swap.
        let pressed = (gp?.buttonB.isPressed ?? false) || (gp?.buttonA.isPressed ?? false)
        if pressed && !resetWasPressed {
            position = initialPosition
            yaw = initialYaw
        }
        resetWasPressed = pressed

        // Hard walls: clamp into the boundary after all movement (incl. reset, whose
        // initialPosition is inside). Hitting an edge fully stops travel on that axis.
        if let b = boundary { position = simd_clamp(position, b.min, b.max) }
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

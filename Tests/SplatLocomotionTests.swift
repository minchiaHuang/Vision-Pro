import Testing
import simd
@testable import VisitingArtisan

/// `SplatLocomotion` integrates gamepad + on-screen `manual` input into yaw/position
/// for the walkable splat world. A pure value type — tested with `gamepad: nil` and a
/// supplied `manual` snapshot (the no-controller fallback).
struct SplatLocomotionTests {

    @Test func manualForwardMovesAlongYawForward() {
        var loco = SplatLocomotion(position: .zero, span: 1)
        loco.tick(deltaTime: 1, gamepad: nil, manual: .init(forward: 1, turn: 0))
        // speed = span(1) * moveFraction(0.6) * dt(1) = 0.6; forward at yaw 0 = (0,0,-1)
        #expect(abs(loco.position.z - (-0.6)) < 1e-5)
        #expect(abs(loco.position.x) < 1e-5)
    }

    @Test func manualTurnRotatesYaw() {
        var loco = SplatLocomotion(position: .zero, span: 1)
        loco.tick(deltaTime: 1, gamepad: nil, manual: .init(forward: 0, turn: 1))
        // yaw -= turn * lookSpeed(2.4) * dt
        #expect(abs(loco.yaw - (-2.4)) < 1e-5)
    }

    @Test func speedScalesWithSpanAndDeltaTime() {
        var loco = SplatLocomotion(position: .zero, span: 10)
        loco.tick(deltaTime: 0.5, gamepad: nil, manual: .init(forward: 1, turn: 0))
        // speed = 10 * 0.6 * 0.5 = 3
        #expect(abs(loco.position.z - (-3)) < 1e-4)
    }

    @Test func noInputLeavesPoseUnchanged() {
        var loco = SplatLocomotion(position: [1, 0, 2], span: 1)
        loco.tick(deltaTime: 1, gamepad: nil, manual: .init())
        #expect(loco.position == [1, 0, 2])
        #expect(loco.yaw == 0)
    }

    @Test func playerTransformPlacesPositionInTranslationColumn() {
        let loco = SplatLocomotion(position: [3, 1, 4], span: 1)
        let m = loco.playerTransform()
        #expect(abs(m.columns.3.x - 3) < 1e-6)
        #expect(abs(m.columns.3.y - 1) < 1e-6)
        #expect(abs(m.columns.3.z - 4) < 1e-6)
    }

    // MARK: - Hard-wall boundary (BA396/Museum world)

    @Test func boundaryStopsForwardTravelAtFarWall() {
        var loco = SplatLocomotion(position: .zero, span: 10)
        loco.boundary = .init(min: [-5, 0, -5], max: [5, 3, 5])
        // forward (yaw 0) walks toward -z; many big steps would blow past -5 without a wall.
        for _ in 0..<20 {
            loco.tick(deltaTime: 1, gamepad: nil, manual: .init(forward: 1, turn: 0))
        }
        #expect(abs(loco.position.z - (-5)) < 1e-5)   // clamped at the wall, not beyond
    }

    @Test func boundaryClampsVerticalBetweenFloorAndCeiling() {
        // A boundary box with floor y=0, ceiling y=2.
        var up = SplatLocomotion(position: [0, 1.9, 0], span: 1)
        up.boundary = .init(min: [-5, 0, -5], max: [5, 2, 5])
        // Trigger lift uses the gamepad; with nil gamepad, drive Y directly via position then tick.
        up.position.y = 99            // simulate an overshoot before the clamp runs
        up.tick(deltaTime: 1, gamepad: nil, manual: .init())
        #expect(abs(up.position.y - 2) < 1e-5)        // capped at the ceiling

        var down = SplatLocomotion(position: [0, 0, 0], span: 1)
        down.boundary = .init(min: [-5, 0, -5], max: [5, 2, 5])
        down.position.y = -99         // simulate sinking through the floor
        down.tick(deltaTime: 1, gamepad: nil, manual: .init())
        #expect(abs(down.position.y - 0) < 1e-5)      // caught at the floor
    }

    @Test func noBoundaryLeavesMovementUnbounded() {
        // Splat-path regression guard: nil boundary must not clamp anything.
        var loco = SplatLocomotion(position: .zero, span: 100)
        for _ in 0..<5 {
            loco.tick(deltaTime: 1, gamepad: nil, manual: .init(forward: 1, turn: 0))
        }
        // 5 steps * (100 * 0.6) = 300 along -z, no wall to stop it.
        #expect(abs(loco.position.z - (-300)) < 1e-3)
    }

    // MARK: - SplatManualInput (thread-safe on-screen fallback)

    @Test func manualInputStoresAndResetsSnapshot() {
        let input = SplatManualInput.shared
        input.set(forward: 0.7, turn: -0.3)
        #expect(input.snapshot().forward == 0.7)
        #expect(input.snapshot().turn == -0.3)
        input.reset()
        #expect(input.snapshot().forward == 0)
        #expect(input.snapshot().turn == 0)
    }
}

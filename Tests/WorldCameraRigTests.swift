import Testing
import simd
@testable import VisitingArtisan

/// `WorldCameraRig` holds first-person camera state (yaw/pitch/position) and the
/// math that touch + gamepad both drive. Pure transforms — tested camera-less.
@MainActor
struct WorldCameraRigTests {

    @Test func cameralessConfigureSetsPositionSpanAndZeroAngles() {
        let rig = WorldCameraRig()
        rig.configure(position: [1, 2, 3], span: 4)
        #expect(rig.position == [1, 2, 3])
        #expect(rig.span == 4)
        #expect(rig.yaw == 0)
        #expect(rig.pitch == 0)
    }

    @Test func tickWithoutGamepadIsANoOp() {
        let rig = WorldCameraRig()
        rig.configure(position: [1, 2, 3], span: 4)
        rig.tick(deltaTime: 1, gamepad: nil)
        #expect(rig.position == [1, 2, 3])
        #expect(rig.yaw == 0)
        #expect(rig.pitch == 0)
    }

    @Test func lookTurnsYawAndPitchByTheGestureScale() {
        let yawRig = WorldCameraRig()
        yawRig.configure(position: .zero, span: 1)
        yawRig.look(deltaX: 100, deltaY: 0)
        #expect(abs(yawRig.yaw - (-100 * 0.005)) < 1e-6)   // yaw -= dx * 0.005

        let pitchRig = WorldCameraRig()
        pitchRig.configure(position: .zero, span: 1)
        pitchRig.look(deltaX: 0, deltaY: 100)
        #expect(abs(pitchRig.pitch - (100 * 0.005)) < 1e-6)
    }

    @Test func pitchClampsJustUnderVertical() {
        let up = WorldCameraRig()
        up.configure(position: .zero, span: 1)
        up.look(deltaX: 0, deltaY: 1_000_000)
        #expect(abs(up.pitch - .pi * 0.49) < 1e-4)

        let down = WorldCameraRig()
        down.configure(position: .zero, span: 1)
        down.look(deltaX: 0, deltaY: -1_000_000)
        #expect(abs(down.pitch - (-.pi * 0.49)) < 1e-4)
    }

    @Test func dollyMovesAlongYawForwardScaledBySpan() {
        let rig = WorldCameraRig()
        rig.configure(position: .zero, span: 2)   // yaw 0 → forward = (0,0,-1)
        rig.dolly(delta: 1)                        // += forward * (1 * 2 * 0.5 = 1)
        #expect(abs(rig.position.z - (-1)) < 1e-6)
        #expect(abs(rig.position.x) < 1e-6)
    }

    @Test func resetRestoresTheInitialViewpoint() {
        let rig = WorldCameraRig()
        rig.configure(position: [5, 0, 0], span: 1)
        rig.look(deltaX: 50, deltaY: 50)
        rig.dolly(delta: 1)
        rig.resetToInitial()
        #expect(rig.position == [5, 0, 0])
        #expect(rig.yaw == 0)
        #expect(rig.pitch == 0)
    }

    /// At zero rotation the view matrix is just the inverse translation.
    @Test func viewMatrixInvertsTranslationAtZeroRotation() {
        let rig = WorldCameraRig()
        rig.configure(position: [1, 2, 3], span: 1)
        let v = rig.viewMatrix()
        #expect(abs(v.columns.3.x - (-1)) < 1e-5)
        #expect(abs(v.columns.3.y - (-2)) < 1e-5)
        #expect(abs(v.columns.3.z - (-3)) < 1e-5)
    }
}

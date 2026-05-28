#if !os(visionOS)
import SwiftUI
import RealityKit

/// 6DoF spike (iOS / iPadOS) — full-screen view that loads a USDZ scene,
/// lets the user drag to look around, and walks with a virtual joystick.
///
/// Eye height is fixed at 1.7 m. Movement is constrained to the X–Z plane
/// (no flying); pitch only affects where the camera looks, not where it
/// walks. Speed is ~1.5 m/s at full joystick deflection.
struct Scene3DView: View {
    let world: World

    // Look gesture state — drag rotates the camera rig.
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var liveYaw: Float = 0
    @State private var livePitch: Float = 0

    // Joystick → translates the camera rig on X–Z.
    @State private var joystick: SIMD2<Float> = .zero
    @State private var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 1.7, 0)

    private let dragSensitivity: Float = 0.005
    private let maxPitch: Float = .pi * 0.45
    private let walkSpeed: Float = 1.5 // m / s at full deflection

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RealityView { content in
                let scene = await SceneLoader.loadScene(for: world)
                scene.name = "world_scene"
                content.add(scene)

                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 70
                let rig = Entity()
                rig.name = "camera_rig"
                rig.position = cameraPosition
                rig.addChild(camera)
                content.add(rig)
            } update: { content in
                guard let rig = content.entities.first(where: { $0.name == "camera_rig" }) else { return }
                let appliedYaw = yaw + liveYaw
                let appliedPitch = clampedPitch(pitch + livePitch)
                rig.orientation =
                    simd_quatf(angle: appliedYaw, axis: [0, 1, 0]) *
                    simd_quatf(angle: appliedPitch, axis: [1, 0, 0])
                rig.position = cameraPosition
            }
            .gesture(lookGesture)
            .ignoresSafeArea()
            .background(Color.black)

            // Joystick overlay — pinned bottom-leading, hit testing isolated to
            // its own circular shape so drag-to-look stays available elsewhere.
            VirtualJoystick(value: $joystick)
                .padding(.leading, 28)
                .padding(.bottom, 36)

            // Top-trailing chrome
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Label("Exit", systemImage: "xmark")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)

                Text("6DoF spike — drag to look, joystick to walk")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(8)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .task(id: world.id) {
            await runWalkLoop()
        }
    }

    // MARK: - Walk loop

    /// Runs a ~60 Hz async loop that turns joystick input into camera
    /// translation. Cancels automatically when the view is dismissed or the
    /// world identity changes.
    private func runWalkLoop() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            let dt = Float(now.timeIntervalSince(last))
            last = now

            // Skip if the joystick is at rest.
            guard simd_length(joystick) > 0.001 else { continue }

            let appliedYaw = yaw + liveYaw

            // Camera-forward and camera-right in world space, on the X-Z plane.
            // With yaw = 0 the camera looks down -Z, so forward = (-sin, 0, -cos).
            let forward = SIMD3<Float>(-sin(appliedYaw), 0, -cos(appliedYaw))
            let right   = SIMD3<Float>( cos(appliedYaw), 0, -sin(appliedYaw))

            let forwardMag: Float = joystick.y * walkSpeed * dt
            let strafeMag:  Float = joystick.x * walkSpeed * dt
            let delta: SIMD3<Float> = forward * forwardMag + right * strafeMag

            cameraPosition += delta
        }
    }

    // MARK: - Look gesture

    private var lookGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                liveYaw = Float(value.translation.width) * dragSensitivity
                livePitch = Float(value.translation.height) * dragSensitivity
            }
            .onEnded { _ in
                yaw += liveYaw
                pitch = clampedPitch(pitch + livePitch)
                liveYaw = 0
                livePitch = 0
            }
    }

    private func clampedPitch(_ value: Float) -> Float {
        min(max(value, -maxPitch), maxPitch)
    }
}
#endif

#if !os(visionOS)
import SwiftUI
import RealityKit

/// 6DoF spike (iOS / iPadOS) — full-screen view that loads a USDZ scene
/// and lets the user drag to look around. Joystick walking will be added
/// in Day 2 of the spike. Eye height ~1.7 m, camera at origin in scene space.
struct Scene3DView: View {
    let world: World

    @State private var yaw: Float = 0    // committed yaw (radians)
    @State private var pitch: Float = 0  // committed pitch (radians)
    @State private var liveYaw: Float = 0
    @State private var livePitch: Float = 0

    private let dragSensitivity: Float = 0.005
    private let maxPitch: Float = .pi * 0.45

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RealityView { content in
                // Load the world's USDZ (or fallback placeholder).
                let scene = await SceneLoader.loadScene(for: world)
                scene.name = "world_scene"
                content.add(scene)

                // Camera at eye height. Anchor so we can rotate it by yaw/pitch.
                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 70
                let rig = Entity()
                rig.name = "camera_rig"
                rig.position = SIMD3<Float>(0, 1.7, 0)
                rig.addChild(camera)
                content.add(rig)
            } update: { content in
                guard let rig = content.entities.first(where: { $0.name == "camera_rig" }) else { return }
                let appliedYaw = yaw + liveYaw
                let appliedPitch = clampedPitch(pitch + livePitch)
                rig.orientation =
                    simd_quatf(angle: appliedYaw, axis: [0, 1, 0]) *
                    simd_quatf(angle: appliedPitch, axis: [1, 0, 0])
            }
            .gesture(dragGesture)
            .ignoresSafeArea()
            .background(Color.black)

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Label("Exit", systemImage: "xmark")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)

                Text("6DoF spike — drag to look around")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }

    private var dragGesture: some Gesture {
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

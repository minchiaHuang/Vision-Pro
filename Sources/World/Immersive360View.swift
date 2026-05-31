#if !os(visionOS)
import SwiftUI
import RealityKit
import UIKit

/// iOS/iPadOS 360-degree view using an inward-facing equirectangular sphere.
struct Immersive360View: View {
    let world: World
    var overrideImage: UIImage? = nil

    @State private var committed = SIMD2<Float>(0, 0)
    @State private var live = SIMD2<Float>(0, 0)
    @State private var useGyro = false
    @State private var motion = MotionManager()

    private let dragSensitivity: Float = 0.004
    private let maxPitch: Float = .pi * 0.42

    private var gyroActive: Bool { useGyro && motion.isAvailable }

    var body: some View {
        RealityView { content in
            let camera = PerspectiveCamera()
            camera.position = .zero
            content.add(camera)

            let sphere = await makeSkySphere()
            sphere.name = "sky"
            content.add(sphere)
        } update: { content in
            guard let sky = content.entities.first(where: { $0.name == "sky" }) else { return }
            if gyroActive {
                sky.orientation = motion.orientation
            } else {
                let yaw = committed.x + live.x
                let pitch = committed.y + live.y
                sky.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                    * simd_quatf(angle: pitch, axis: [1, 0, 0])
            }
        }
        .gesture(dragGesture)
        .overlay(alignment: .topTrailing) { controls }
        .background(Color.black)
        .onChange(of: useGyro) { _, isOn in
            if isOn {
                motion.start()
                motion.recenter()
            } else {
                motion.stop()
            }
        }
        .onDisappear { motion.stop() }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !gyroActive else { return }
                let yawDelta = Float(value.translation.width) * dragSensitivity
                let pitchDelta = Float(value.translation.height) * dragSensitivity
                let nextPitch = clampedPitch(committed.y + pitchDelta)
                live = SIMD2(yawDelta, nextPitch - committed.y)
            }
            .onEnded { _ in
                guard !gyroActive else { return }
                committed = SIMD2(committed.x + live.x, clampedPitch(committed.y + live.y))
                live = .zero
            }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button {
                useGyro.toggle()
            } label: {
                Label(useGyro ? "Gyro" : "Drag",
                      systemImage: useGyro ? "gyroscope" : "hand.draw")
                    .font(.footnote.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!motion.isAvailable)

            if gyroActive {
                Button {
                    motion.recenter()
                } label: {
                    Label("Recenter", systemImage: "scope")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    /// Builds the inward-facing sphere used as the panorama surface.
    /// Uses `overrideImage` (e.g. a downloaded panorama) when present, else the bundled asset.
    private func makeSkySphere() async -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()

        // Asset lookup + image decode is the expensive part; do it off the main
        // actor so it doesn't block the frame that presents the panorama.
        let cgImage = await Self.decodePanorama(override: overrideImage, imageName: world.imageName)
        if let cgImage,
           let texture = try? await TextureResource(
            image: cgImage,
            withName: nil,
            options: .init(semantic: .color)
           ) {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            material.color = .init(tint: .init(white: 0.25, alpha: 1))
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.scale = SIMD3(-1, 1, 1)
        return entity
    }

    /// Decodes the panorama CGImage on a background task (off the main actor).
    private static func decodePanorama(override: UIImage?, imageName: String) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            (override ?? UIImage(named: imageName))?.cgImage
        }.value
    }

    private func clampedPitch(_ pitch: Float) -> Float {
        min(max(pitch, -maxPitch), maxPitch)
    }
}
#endif

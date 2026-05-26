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

    private let dragSensitivity: Float = 0.004
    private let maxPitch: Float = .pi * 0.42

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
            let yaw = committed.x + live.x
            let pitch = committed.y + live.y
            sky.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let yawDelta = Float(value.translation.width) * dragSensitivity
                    let pitchDelta = Float(value.translation.height) * dragSensitivity
                    let nextPitch = clampedPitch(committed.y + pitchDelta)
                    live = SIMD2(yawDelta, nextPitch - committed.y)
                }
                .onEnded { _ in
                    committed = SIMD2(committed.x + live.x, clampedPitch(committed.y + live.y))
                    live = .zero
                }
        )
        .background(Color.black)
    }

    /// Builds the inward-facing sphere used as the panorama surface.
    /// Uses `overrideImage` (e.g. a downloaded panorama) when present, else the bundled asset.
    private func makeSkySphere() async -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()

        let cgImage = (overrideImage ?? UIImage(named: world.imageName))?.cgImage
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

    private func clampedPitch(_ pitch: Float) -> Float {
        min(max(pitch, -maxPitch), maxPitch)
    }
}
#endif

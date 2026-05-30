#if os(visionOS)
import SwiftUI
import RealityKit
import UIKit

/// visionOS: true immersion. Maps the 360° image onto the inner wall of a large sphere;
/// the user's head is the camera (head tracking).
struct ImmersiveWorldView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        RealityView { content in
            let sphere = await makeSkySphere(
                override: appState.generatedPano,
                imageName: appState.world?.imageName ?? WorldCatalog.fallback.imageName
            )
            content.add(sphere)
        }
    }

    /// Prefers a runtime panorama (e.g. World Labs) when present, else the bundled asset.
    private func makeSkySphere(override: UIImage?, imageName: String) async -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()

        if let cgImage = (override ?? UIImage(named: imageName))?.cgImage,
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
        entity.scale = SIMD3(-1, 1, 1)   // Flip inside-out so the texture faces inward
        return entity
    }
}
#endif

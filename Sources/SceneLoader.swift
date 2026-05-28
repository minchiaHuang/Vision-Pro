import Foundation
import RealityKit

/// 6DoF spike — loads a USDZ scene from the bundle, with a graceful fallback
/// when the world has no scene asset yet (e.g. starry_night, quiet_solitary).
///
/// Usage:
///   let entity = await SceneLoader.loadScene(for: world)
///   content.add(entity)
enum SceneLoader {

    /// Returns a renderable entity for the given world.
    /// If `world.sceneName` is nil, returns a gray placeholder cube so the
    /// app keeps running while remaining USDZ assets are sourced.
    static func loadScene(for world: World) async -> Entity {
        if let name = world.sceneName,
           let entity = try? await Entity(named: name, in: nil) {
            return entity
        }
        return placeholder(label: "USDZ not available")
    }

    /// Gray cube + missing-asset label. Sits at the floor so the camera
    /// (eye height ~1.7 m) sees it in front.
    private static func placeholder(label: String) -> Entity {
        let mesh = MeshResource.generateBox(size: 0.5)
        var material = SimpleMaterial()
        material.color = .init(tint: .init(white: 0.35, alpha: 1))
        material.roughness = 1.0
        material.metallic = 0.0

        let cube = ModelEntity(mesh: mesh, materials: [material])
        cube.position = SIMD3<Float>(0, 0.25, -2.0)
        cube.name = "scene_placeholder"

        return cube
    }
}

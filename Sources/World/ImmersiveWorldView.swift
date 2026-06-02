#if os(visionOS)
import SwiftUI
import RealityKit
import UIKit
import GameController

/// visionOS: true immersion. Two paths, mirroring the iOS `iOSWorldView` priority:
///   - parametric USDZ walk-in world when `worldParams` is set (the production experience);
///   - 360° panorama sphere otherwise (e.g. the World Labs panorama-only flow).
/// In the parametric world the head is the camera (head tracking) AND a game controller
/// drives artificial locomotion (reusing `SplatLocomotion`), so the user can walk through
/// worlds larger than the room — matching the iPad experience.
struct ImmersiveWorldView: View {
    @Environment(AppState.self) private var appState
    /// Retains the per-frame locomotion state + scene subscription across updates.
    @State private var locomotor = ParametricLocomotor()

    var body: some View {
        RealityView { content in
            if let params = appState.worldParams,
               let build = await ParametricWorldBuilder.build(params: params) {
                // Rest the model's floor at the origin and centre it horizontally so the user
                // stands inside the world.
                build.container.position = SIMD3(-build.bounds.center.x,
                                                 -build.bounds.min.y,
                                                 -build.bounds.center.z)
                // axis 4 saturation: immersive RealityView has no full-screen
                // `.blendMode(.saturation)` overlay (iOS's approach), so bake it into the
                // model's material tints instead.
                ParametricWorldBuilder.applySaturation(build.container, saturation: params.saturation)
                // Wrap the world in a root entity that locomotion moves each frame
                // (player walks → world shifts opposite); head tracking adds local 6DoF
                // on top.
                let root = Entity()
                root.addChild(build.container)
                content.add(root)
                locomotor.start(root: root, span: build.span, content: content)
            } else {
                let sphere = await makeSkySphere(
                    override: appState.generatedPano,
                    imageName: appState.world?.imageName ?? WorldCatalog.fallback.imageName
                )
                content.add(sphere)
            }
        }
    }

    /// Prefers a runtime panorama (e.g. World Labs) when present, else the bundled asset.
    private func makeSkySphere(override: UIImage?, imageName: String) async -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()

        // Asset lookup + image decode is the expensive part; do it off the main
        // actor so it doesn't block the frame that presents the immersive world.
        let cgImage = await Self.decodePanorama(override: override, imageName: imageName)
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
        entity.scale = SIMD3(-1, 1, 1)   // Flip inside-out so the texture faces inward
        return entity
    }

    /// Decodes the panorama CGImage on a background task (off the main actor).
    private static func decodePanorama(override: UIImage?, imageName: String) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            (override ?? UIImage(named: imageName))?.cgImage
        }.value
    }
}

/// Owns the parametric world's locomotion state and the `SceneEvents.Update`
/// subscription (held via `@State` so it isn't cancelled). Each frame it ticks
/// `SplatLocomotion` from the game controller and moves the world root by the
/// inverse player transform, so the user walks through the scene; head tracking
/// still supplies local 6DoF on top. All on the main actor.
@MainActor
final class ParametricLocomotor {
    private var loco = SplatLocomotion()
    private weak var root: Entity?
    private var subscription: EventSubscription?

    func start(root: Entity, span: Float, content: RealityViewContent) {
        self.root = root
        // User already stands inside the floor-aligned world, so start at the origin
        // (no back-off, unlike the splat path). Speed scales with scene size.
        self.loco = SplatLocomotion(position: .zero, span: span)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self, let root = self.root else { return }
            let gamepad = SplatSpikeDebug.ignoreGamepad ? nil : currentExtendedGamepad()
            self.loco.tick(deltaTime: Float(event.deltaTime), gamepad: gamepad)
            root.transform = Transform(matrix: self.loco.playerTransform().inverse)
        }
    }
}

/// First connected controller's extended gamepad, or nil (same pattern as the splat
/// renderer). Polled per frame on the main actor.
private func currentExtendedGamepad() -> GCExtendedGamepad? {
    GCController.controllers().lazy.compactMap { $0.extendedGamepad }.first
}
#endif

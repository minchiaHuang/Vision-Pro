#if os(visionOS)
import SwiftUI
import RealityKit

/// visionOS first-person walk-in for the USDZ Dev viewer, matching the iPad
/// `USDZTestView` experience. The head is the camera (head tracking) AND a game controller
/// drives artificial locomotion (reusing `SplatLocomotion`), so the user can walk through
/// models larger than the room. Opened as the `usdz` immersive space; the model name is
/// passed as the space's value. DEV / verification only.
struct ImmersiveUSDZView: View {
    let modelName: String

    @State private var gamepad = GamepadManager()
    /// Retains the per-frame locomotion state + scene subscription across updates.
    @State private var locomotor = USDZLocomotor()

    var body: some View {
        RealityView { content in
            guard let model = try? await Entity(named: modelName) else { return }

            // Floor-align + centre so the user stands inside the model at the origin
            // (same framing as the parametric immersive world).
            let bounds = model.visualBounds(relativeTo: nil)
            let span = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            let container = Entity()
            container.addChild(model)
            container.position = SIMD3(-bounds.center.x, -bounds.min.y, -bounds.center.z)

            // Three directional lights, mirroring the iOS USDZ viewer.
            for dir in [SIMD3<Float>(1, 1, 1), SIMD3<Float>(-1, 0.6, -0.6), SIMD3<Float>(0, 0.4, 1)] {
                let light = DirectionalLight()
                light.light.intensity = 1500
                light.look(at: .zero, from: dir, relativeTo: nil)
                container.addChild(light)
            }

            // Wrap in a root entity that locomotion moves each frame (player walks →
            // world shifts opposite); head tracking adds local 6DoF on top.
            let root = Entity()
            root.addChild(container)
            content.add(root)
            locomotor.start(root: root, span: span, content: content, gamepad: gamepad)
        }
    }
}

/// Owns the USDZ walk-in's locomotion state and the `SceneEvents.Update` subscription
/// (held via `@State` so it isn't cancelled). Each frame it ticks `SplatLocomotion` from
/// the game controller and moves the world root by the inverse player transform; head
/// tracking still supplies local 6DoF on top. Mirrors the parametric world's locomotor.
@MainActor
final class USDZLocomotor {
    private var loco = SplatLocomotion()
    private weak var root: Entity?
    private var subscription: EventSubscription?

    func start(root: Entity, span: Float, content: RealityViewContent, gamepad: GamepadManager) {
        self.root = root
        // User already stands inside the floor-aligned model, so start at the origin.
        // Speed scales with model size.
        self.loco = SplatLocomotion(position: .zero, span: span)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self, let root = self.root else { return }
            let pad = SplatSpikeDebug.ignoreGamepad ? nil : gamepad.gamepad
            self.loco.tick(deltaTime: Float(event.deltaTime), gamepad: pad)
            root.transform = Transform(matrix: self.loco.playerTransform().inverse)
        }
    }
}
#endif

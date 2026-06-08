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
    /// Streams the Future Museum paintings onto the gallery walls as Stage B finishes each one
    /// (the user enters the moment the story is ready, before any image has landed).
    @State private var wallStreamer = GalleryWallStreamer()
    /// Gentle looping background music for the duration of the immersive gallery visit.
    @State private var music = MuseumMusicPlayer()

    var body: some View {
        // Observe each painting's arrival: reading every node's `image` here ties this view's
        // re-evaluation to Stage B landings, which re-runs the RealityView `update:` closure
        // below so the walls re-texture as images stream in.
        let _ = appState.museumGenerator.nodes.map(\.image)
        return RealityView { content in
            if let params = appState.worldParams,
               let build = await ParametricWorldBuilder.build(params: params,
                                                              galleryPhotos: appState.galleryImages) {
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
                // Future Museum: narrate each beat as the walker approaches its wall frame.
                // Same ordered `galleryFrames` list as the wall images, so frame i == beat i.
                if let story = appState.museumStory {
                    let frames = Array(ParametricWorldBuilder.galleryFrames(build.container)
                        .prefix(story.nodes.count))
                    let positions = frames.map { $0.position(relativeTo: root) }
                    let director = MuseumNarrationDirector(framePositions: positions,
                                                           story: story,
                                                           convo: appState.museumConversation)
                    locomotor.start(root: root, span: build.span, content: content) { player in
                        director.tick(playerPosition: player)
                    }
                } else {
                    locomotor.start(root: root, span: build.span, content: content)
                }
                // Hand the world root to the streamer and paint whatever has already landed;
                // the `update:` closure below picks up the rest as they arrive.
                wallStreamer.root = root
                wallStreamer.applyIfNeeded(generator: appState.museumGenerator)
            } else {
                let sphere = await makeSkySphere(
                    override: appState.generatedPano,
                    imageName: appState.world?.imageName ?? WorldCatalog.fallback.imageName
                )
                content.add(sphere)
            }
        } update: { _ in
            // Re-runs whenever the generator's observable nodes change (a painting landed);
            // re-textures only the slots whose images are now ready. No-op for the sky-sphere
            // path (the streamer has no root there).
            wallStreamer.applyIfNeeded(generator: appState.museumGenerator)
        }
        .onAppear { music.start() }
        .onDisappear { music.stop() }
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

    private var onPlayerMove: ((SIMD3<Float>) -> Void)?

    func start(root: Entity, span: Float, content: RealityViewContent,
               onPlayerMove: ((SIMD3<Float>) -> Void)? = nil) {
        self.root = root
        self.onPlayerMove = onPlayerMove
        // User already stands inside the floor-aligned world, so start at the origin
        // (no back-off, unlike the splat path). Speed scales with scene size.
        self.loco = SplatLocomotion(position: .zero, span: span)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self, let root = self.root else { return }
            let gamepad = SplatSpikeDebug.ignoreGamepad ? nil : currentExtendedGamepad()
            self.loco.tick(deltaTime: Float(event.deltaTime), gamepad: gamepad)
            let player = self.loco.playerTransform()
            root.transform = Transform(matrix: player.inverse)
            // Report the player's scene-space position (root-local) for proximity narration.
            let t = player.columns.3
            self.onPlayerMove?(SIMD3(t.x, t.y, t.z))
        }
    }
}

/// First connected controller's extended gamepad, or nil (same pattern as the splat
/// renderer). Polled per frame on the main actor.
private func currentExtendedGamepad() -> GCExtendedGamepad? {
    GCController.controllers().lazy.compactMap { $0.extendedGamepad }.first
}

/// Streams the Future Museum's five paintings onto the gallery walls as Stage B finishes each
/// one. Held in the immersive view's `@State` (a class, so the reference is stable across view
/// updates and its `root`/signature mutations don't churn SwiftUI state). The view's RealityView
/// `update:` closure calls `applyIfNeeded` — which reads the generator's `@Observable` nodes, so
/// the closure re-runs as each image lands.
@MainActor
final class GalleryWallStreamer {
    /// The world root entity (set once the immersive world is built). Frames live in its subtree.
    weak var root: Entity?
    /// Per-beat "image has landed" flags from the last re-texture, so we re-apply only on change.
    private var appliedSignature: [Bool] = []

    /// Re-textures the walls iff the set of landed paintings changed since the last apply. Cheap:
    /// at most five re-applies per run. Placeholder slots (image not yet landed) keep a neutral
    /// panel via `orderedGalleryImages()`, so the beat→wall mapping never shifts.
    func applyIfNeeded(generator: MuseumGenerator) {
        guard let root else { return }
        let signature = generator.nodes.map { $0.image != nil }   // reads observable → drives re-run
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        let textures = ParametricWorldBuilder.texturesFrom(generator.orderedGalleryImages())
        ParametricWorldBuilder.applyGalleryPhotos(root, textures: textures)
    }
}

/// Speaks each beat's narration once, when the walker first comes within `radius` metres of that
/// beat's wall frame. Frame order == beat order (the same `ParametricWorldBuilder.galleryFrames`
/// list drives the wall images), so frame *i* narrates `story.nodes[i]`. Narration is spoken
/// through the shared `ConversationService`, so it shares the audio session with push-to-talk.
@MainActor
final class MuseumNarrationDirector {
    private let frameXZ: [SIMD2<Float>]
    private let narrations: [String]
    private let tones: [String]
    private let decisionPrompt: String
    private weak var convo: ConversationService?
    private let radius: Float
    private var fired: Set<Int> = []

    init(framePositions: [SIMD3<Float>], story: MuseumStory,
         convo: ConversationService?, radius: Float = 2.5) {
        self.frameXZ = framePositions.map { SIMD2($0.x, $0.z) }
        self.narrations = story.nodes.map(\.narration)
        self.tones = story.nodes.map(\.tone)
        self.decisionPrompt = story.decision_prompt
        self.convo = convo
        self.radius = radius
    }

    /// Called each locomotion frame with the player's scene-space position. The warm Elixir beat
    /// closes with the decision prompt — the museum's final question, handed back to the visitor.
    func tick(playerPosition: SIMD3<Float>) {
        let p = SIMD2(playerPosition.x, playerPosition.z)
        guard let i = Self.frameToTrigger(playerXZ: p, frameXZ: frameXZ, fired: fired, radius: radius),
              i < narrations.count else { return }
        fired.insert(i)
        var line = narrations[i]
        if tones[i] == "warm", !decisionPrompt.isEmpty {
            line += " " + decisionPrompt
        }
        convo?.narrate(line)
    }

    /// Pure: the nearest not-yet-fired frame within `radius`, or nil. Kept free of RealityKit so
    /// the trigger rule is testable in isolation.
    static func frameToTrigger(playerXZ: SIMD2<Float>, frameXZ: [SIMD2<Float>],
                               fired: Set<Int>, radius: Float) -> Int? {
        let r2 = radius * radius
        func d2(_ i: Int) -> Float {
            let dx = playerXZ.x - frameXZ[i].x, dy = playerXZ.y - frameXZ[i].y
            return dx * dx + dy * dy
        }
        return frameXZ.indices
            .filter { !fired.contains($0) && d2($0) <= r2 }
            .min { d2($0) < d2($1) }
    }
}
#endif

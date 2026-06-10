#if os(visionOS)
import SwiftUI
import RealityKit
import UIKit
import GameController
import ARKit
import QuartzCore

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
    /// Holds the BA396 plaque entities so their transforms can be re-applied live from
    /// `PlaqueTuning` (the TEMP slider panel in the gallery controls).
    @State private var plaqueTuner = PlaqueTuner()

    var body: some View {
        // Observe each painting's arrival: reading every node's `image` here ties this view's
        // re-evaluation to Stage B landings, which re-runs the RealityView `update:` closure
        // below so the walls re-texture as images stream in.
        let _ = appState.museumGenerator.nodes.map(\.image)
        // Subscribe to live plaque tuning: reading these makes a slider drag re-run `update:`.
        let tuning = PlaqueTuning.shared
        let _ = (tuning.sideOffset, tuning.sideSign, tuning.vertical, tuning.outward, tuning.scale, tuning.faceFlip)
        return RealityView { content, attachments in
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
                // BA396: read the portrait walls' physical anchors (root space) once. The shared
                // clockwise `build.visitOrder` keys both the fixed spawn pose (stand in front of
                // the first wall, facing it) and the plaque placement, so wall i, plaque i and the
                // walk all agree. Empty / nil for other worlds (→ spawn at the origin as before).
                let ba396Anchors = params.archetype == .ba396Museum
                    ? ParametricWorldBuilder.ba396PlaqueAnchors(root, relativeTo: root)
                    : []
                let spawn = params.archetype == .ba396Museum
                    ? ParametricWorldBuilder.ba396SpawnPose(anchors: ba396Anchors,
                                                            order: build.visitOrder)
                    : nil
                // Future Museum: narrate each beat as the walker approaches its wall frame.
                // Same ordered `galleryFrames` list as the wall images, so frame i == beat i.
                if let story = appState.museumStory {
                    let frames = Array(ParametricWorldBuilder.galleryFrames(build.container)
                        .prefix(story.nodes.count))
                    let positions = frames.map { $0.position(relativeTo: root) }
                    let director = MuseumNarrationDirector(framePositions: positions,
                                                           story: story,
                                                           convo: appState.museumConversation)
                    locomotor.start(root: root, span: build.span, bounds: build.bounds,
                                    content: content, spawn: spawn) { player in
                        director.tick(playerPosition: player)
                    }
                } else {
                    locomotor.start(root: root, span: build.span, bounds: build.bounds,
                                    content: content, spawn: spawn)
                }
                // BA396 Future Museum: hang a museum wall-label beside each portrait. The
                // caption text is ready from Stage A (before any image lands), so the plaques
                // appear while the photos are still "developing". Parented under `root` so they
                // ride locomotion with the walls. Exact placement is tuned on device via the
                // `ba396Plaque*` constants; the Simulator only needs them to appear + be tappable.
                if params.archetype == .ba396Museum {
                    // Real flow uses the generated story; "Visit Old World" / dev entry (no story)
                    // falls back to sample beats so the plaque layout/size is quick to preview.
                    let nodes = appState.museumStory?.nodes ?? BeatPlaqueSample.nodes
                    let order = build.visitOrder
                    var tuned: [PlaqueTuner.Item] = []
                    for (k, node) in nodes.enumerated() {
                        // Beat k sits on the wall visited at step k (same mapping as the images).
                        let tile = k < order.count ? order[k] : k
                        guard ba396Anchors.indices.contains(tile),
                              let plaque = attachments.entity(for: node.id) else { continue }
                        root.addChild(plaque)   // child of root → rides locomotion with the walls
                        tuned.append(.init(entity: plaque,
                                           centroid: ba396Anchors[tile].centroid,
                                           normal: ba396Anchors[tile].normal))
                    }
                    // Position/size/orient comes from PlaqueTuning so it can be tuned live.
                    plaqueTuner.set(tuned)
                    plaqueTuner.reapply(PlaqueTuning.shared)
                }
                // Hand the world root to the streamer and paint whatever has already landed;
                // the `update:` closure below picks up the rest as they arrive.
                wallStreamer.root = root
                wallStreamer.archetype = params.archetype
                wallStreamer.visitOrder = build.visitOrder
                wallStreamer.applyIfNeeded(generator: appState.museumGenerator)
            } else {
                let sphere = await makeSkySphere(
                    override: appState.generatedPano,
                    imageName: appState.world?.imageName ?? WorldCatalog.fallback.imageName
                )
                content.add(sphere)
            }
        } update: { _, _ in
            // Re-runs whenever the generator's observable nodes change (a painting landed);
            // re-textures only the slots whose images are now ready. No-op for the sky-sphere
            // path (the streamer has no root there).
            wallStreamer.applyIfNeeded(generator: appState.museumGenerator)
            // Live plaque tuning: a slider drag (read in `body`) re-runs this and re-places them.
            plaqueTuner.reapply(PlaqueTuning.shared)
        } attachments: {
            // One museum plaque per beat on the BA396 path. Real story when present; otherwise
            // sample beats (so "Visit Old World" / dev entry can preview the plaque layout).
            if appState.worldParams?.archetype == .ba396Museum {
                ForEach(appState.museumStory?.nodes ?? BeatPlaqueSample.nodes) { node in
                    Attachment(id: node.id) {
                        BeatPlaqueView(node: node)
                    }
                }
            }
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

    /// Head-pose source for the fixed first-person eye height — same `WorldTrackingProvider`
    /// pattern as the splat renderer (device-anchor pose needs no usage-description key). Started
    /// in `start()`, then polled each frame for the head's Y so we can pin the eye height.
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    /// Fixed first-person standing eye height (metres above the world floor). Without this the eye
    /// sits at the user's real — possibly seated — head height; we cancel that head Y each frame so
    /// every visitor sees the world from a consistent standing viewpoint. Tunable on device.
    private let eyeHeight: Float = 1.6

    // Hard-wall margins (metres), tunable on device. Inset from the model bounds so the
    // camera never clips into a wall and to absorb wall thickness.
    private let wallMargin: Float = 0.5     // side walls (X/Z)
    private let floorMargin: Float = 0.0    // stand on the floor
    private let ceilingMargin: Float = 0.5  // don't poke through the roof

    func start(root: Entity, span: Float, bounds: BoundingBox, content: RealityViewContent,
               spawn: (position: SIMD3<Float>, yaw: Float)? = nil,
               onPlayerMove: ((SIMD3<Float>) -> Void)? = nil) {
        self.root = root
        self.onPlayerMove = onPlayerMove
        // Spawn at the fixed pose when supplied (BA396: in front of the first wall, facing it),
        // else at the origin (the floor-aligned world centre). Speed scales with scene size.
        self.loco = SplatLocomotion(position: spawn?.position ?? .zero,
                                    yaw: spawn?.yaw ?? 0, span: span)
        // Hard walls. Player origin == bounds.center horizontally and the floor (bounds.min.y)
        // sits at y=0, so player space spans ±extents/2 in X/Z and [0, extents.y] in Y.
        let hx = max(0, bounds.extents.x / 2 - wallMargin)
        let hz = max(0, bounds.extents.z / 2 - wallMargin)
        let top = max(floorMargin, bounds.extents.y - ceilingMargin)
        self.loco.boundary = .init(min: SIMD3(-hx, floorMargin, -hz),
                                   max: SIMD3( hx, top,         hz))
        // First-person: lock vertical so the triggers can't fly the view up/down, and start world
        // tracking so the update closure can pin the eye to a constant standing height (below).
        self.loco.lockVertical = true
        Task { @MainActor in try? await self.arSession.run([self.worldTracking]) }
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self, let root = self.root else { return }
            let gamepad = SplatSpikeDebug.ignoreGamepad ? nil : currentExtendedGamepad()
            self.loco.tick(deltaTime: Float(event.deltaTime), gamepad: gamepad)
            // Pin the eye to a fixed standing height: cancel the real head Y so the view sits at
            // `eyeHeight` above the floor whether the user is seated or standing. Until tracking is
            // ready the anchor is nil and we keep the previous Y (no jump).
            if let device = self.worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                let headY = device.originFromAnchorTransform.columns.3.y
                self.loco.position.y = self.eyeHeight - headY
            }
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
    /// Which world is being textured — selects the correct wall-photo path (BA396 shared atlas vs
    /// the Art Gallery's per-frame "bake" meshes). Set alongside `root` when the world is built.
    var archetype: WorldArchetype?
    /// BA396 clockwise visit order (from `ParametricWorldBuild`): beat k → atlas tile `visitOrder[k]`,
    /// so re-textured walls keep the same chronological order as the initial paint.
    var visitOrder: [Int] = []
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
        let images = generator.orderedGalleryImages()
        if archetype == .ba396Museum {
            // BA396's 6 walls are ONE shared atlas mesh, so re-composite the atlas in the shared
            // clockwise visit order. The gallery `applyGalleryPhotos` path matches mesh names
            // containing "bake" — BA396 has none, so using it here silently no-ops and the walls
            // stay on the dark build-time placeholders.
            ParametricWorldBuilder.applyBA396Portraits(root, images: images, order: visitOrder)
        } else {
            ParametricWorldBuilder.applyGalleryPhotos(root, textures: ParametricWorldBuilder.texturesFrom(images))
        }
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

// MARK: - Plaque live tuning (TEMP dev tool — fold finals into defaults + delete panel later)

/// Live-tunable placement for the BA396 plaques. Shared across the immersive view (which owns the
/// plaque entities) and the gallery-controls window (which hosts the sliders). TEMP: once the
/// numbers are dialed in on device, set these as the defaults and remove the slider panel.
@Observable
final class PlaqueTuning {
    static let shared = PlaqueTuning()
    // Defaults dialed in on the visionOS Simulator (2026-06-09). The plaque positions derive from
    // the fixed BA396 USDZ geometry, so these hold identically on device.
    var sideOffset: Float = 4.01   // metres along the wall from the frame center
    var sideSign: Float = 1        // +1 = right of the frame, −1 = left
    var vertical: Float = -1.40    // metres up(+) / down(−) from the frame center
    var outward: Float = 0.25      // metres out from the wall toward the room
    var scale: Float = 4.97        // plaque entity scale
    var faceFlip = false           // flip 180° if a plaque faces into the wall
}

/// Holds the placed plaque entities + their base anchors so their transforms can be recomputed
/// live from `PlaqueTuning` (slider drag → `reapply`). Local transforms only; the plaques are
/// children of the world root, so they ride locomotion automatically.
@MainActor
final class PlaqueTuner {
    struct Item { let entity: Entity; let centroid: SIMD3<Float>; let normal: SIMD3<Float> }
    private var items: [Item] = []

    func set(_ items: [Item]) { self.items = items }

    func reapply(_ t: PlaqueTuning) {
        for it in items {
            // A horizontal vector lying in the wall plane (⊥ to the normal): the left/right axis.
            let alongRaw = cross(SIMD3<Float>(0, 1, 0), it.normal)
            let along = length(alongRaw) < 1e-5 ? SIMD3<Float>(1, 0, 0) : normalize(alongRaw)
            let pos = it.centroid
                + along * (t.sideOffset * t.sideSign)
                + it.normal * t.outward
                + SIMD3<Float>(0, t.vertical, 0)
            // Orient with `look` (pins world-up) so the label never mirrors/rolls — using
            // `simd_quatf(from:to:)` flipped the card to its back on opposite-facing walls, which
            // showed the text reversed. The attachment's front is +Z, and `look` aims -Z at the
            // target, so aim at (pos − face) to turn +Z toward the room. `look` resets scale, so
            // set scale AFTER it.
            let face = t.faceFlip ? -it.normal : it.normal
            it.entity.look(at: pos - face, from: pos, relativeTo: it.entity.parent)
            it.entity.scale = .init(repeating: t.scale)
        }
    }
}

// MARK: - Sample beats (plaque preview without running generation)

/// Stand-in beats so the BA396 plaques can be previewed via "Visit Old World" (or dev entry)
/// without running the quiz + image generation. Six entries (one per wall) with deliberately
/// mixed caption lengths so the layout/size can be judged on both short and long labels. Used
/// only when `appState.museumStory` is nil; the real flow always supplies its own story.
enum BeatPlaqueSample {
    static let nodes: [MuseumNode] = [
        .init(stage: "ordinary_world_call", age: 17, beat: "",
              caption: "The Drawer — where the dream is kept, unspoken.",
              narration: "Seventeen. You keep the flyer in a drawer. You haven't told anyone yet.",
              image_prompt: "", tone: "cold"),
        .init(stage: "crossing_threshold", age: 19, beat: "",
              caption: "Before Dawn",
              narration: "Then, for years, every morning before the city wakes. No audience. No applause.",
              image_prompt: "", tone: "cold"),
        .init(stage: "ordeal", age: 23, beat: "",
              caption: "The Empty Row — when the body fails and the others have gone.",
              narration: "Twenty-three. Your body gives out. The ones who started with you have already left.",
              image_prompt: "", tone: "cold"),
        .init(stage: "sacrifice", age: 27, beat: "",
              caption: "Missed Calls",
              narration: "You wanted to keep time with your family. You missed the last birthday that mattered.",
              image_prompt: "", tone: "cold"),
        .init(stage: "return_elixir", age: 34, beat: "",
              caption: "Curtain Call — one stage, at last.",
              narration: "Thirty-four. The Opera House. Whether it was worth it — only you will know.",
              image_prompt: "", tone: "warm"),
        .init(stage: "epilogue", age: 40, beat: "",
              caption: "After — a sample sixth label for sizing.",
              narration: "A sixth sample beat so all six BA396 walls show a plaque for layout checking.",
              image_prompt: "", tone: "warm"),
    ]
}

// MARK: - Museum plaque (RealityView attachment)

/// A small museum wall-label shown beside a BA396 portrait. Collapsed it shows the short
/// `caption`; tapping expands it to the full `narration`. Lives inside a `RealityView`
/// attachment, so the tap is an ordinary SwiftUI `Button` — no RealityKit
/// `InputTargetComponent`/`CollisionComponent` plumbing is required. Styled with the shared
/// Oops glass card so it matches the rest of the flow.
struct BeatPlaqueView: View {
    let node: MuseumNode
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(stageLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(OopsGlass.label3)
                Text(node.caption)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(OopsGlass.label1)
                    .fixedSize(horizontal: false, vertical: true)
                if expanded {
                    Text(node.narration)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            // Constant width so expanding only grows downward (no left/right shift on tap).
            .frame(width: 420, alignment: .leading)
            .padding(.vertical, 20)
            .padding(.horizontal, 26)
            .oopsCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .animation(.easeInOut(duration: 0.25), value: expanded)
    }

    /// "ORDEAL · AGE 23" — a quiet exhibit eyebrow above the caption.
    private var stageLabel: String {
        node.stage.replacingOccurrences(of: "_", with: " ").uppercased() + " · AGE \(node.age)"
    }
}
#endif

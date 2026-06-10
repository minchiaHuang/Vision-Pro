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
                // Locomotion only. Per-beat narration is no longer proximity-triggered: each wall
                // plaque now carries a play button that has the Curator generate a fresh spoken
                // description on demand (`BeatPlaqueView` → `ConversationService.describeExhibit`).
                locomotor.start(root: root, span: build.span, bounds: build.bounds, content: content)
                // BA396 Future Museum: hang a museum wall-label beside each portrait. The
                // caption text is ready from Stage A (before any image lands), so the plaques
                // appear while the photos are still "developing". Parented under `root` so they
                // ride locomotion with the walls. Exact placement is tuned on device via the
                // `ba396Plaque*` constants; the Simulator only needs them to appear + be tappable.
                if params.archetype == .ba396Museum {
                    // Real flow uses the generated story; "Visit Old World" / dev entry (no story)
                    // falls back to sample beats so the plaque layout/size is quick to preview.
                    let nodes = appState.museumStory?.nodes ?? BeatPlaqueSample.nodes
                    let anchors = ParametricWorldBuilder.ba396PlaqueAnchors(root, relativeTo: root)
                    var tuned: [PlaqueTuner.Item] = []
                    for (i, node) in nodes.prefix(anchors.count).enumerated() {
                        guard let plaque = attachments.entity(for: node.id) else { continue }
                        root.addChild(plaque)   // child of root → rides locomotion with the walls
                        tuned.append(.init(entity: plaque,
                                           centroid: anchors[i].centroid, normal: anchors[i].normal))
                    }
                    // Position/size/orient comes from PlaqueTuning so it can be tuned live.
                    plaqueTuner.set(tuned)
                    plaqueTuner.reapply(PlaqueTuning.shared)
                }
                // Hand the world root to the streamer and paint whatever has already landed;
                // the `update:` closure below picks up the rest as they arrive.
                wallStreamer.root = root
                wallStreamer.archetype = params.archetype
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
                        BeatPlaqueView(node: node, convo: appState.museumConversation)
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

    // Hard-wall margins (metres), tunable on device. Inset from the model bounds so the
    // camera never clips into a wall and to absorb wall thickness.
    private let wallMargin: Float = 0.5     // side walls (X/Z)
    private let floorMargin: Float = 0.0    // stand on the floor
    private let ceilingMargin: Float = 0.5  // don't poke through the roof

    func start(root: Entity, span: Float, bounds: BoundingBox, content: RealityViewContent,
               onPlayerMove: ((SIMD3<Float>) -> Void)? = nil) {
        self.root = root
        self.onPlayerMove = onPlayerMove
        // User already stands inside the floor-aligned world, so start at the origin
        // (no back-off, unlike the splat path). Speed scales with scene size.
        self.loco = SplatLocomotion(position: .zero, span: span)
        // Hard walls. Player origin == bounds.center horizontally and the floor (bounds.min.y)
        // sits at y=0, so player space spans ±extents/2 in X/Z and [0, extents.y] in Y.
        let hx = max(0, bounds.extents.x / 2 - wallMargin)
        let hz = max(0, bounds.extents.z / 2 - wallMargin)
        let top = max(floorMargin, bounds.extents.y - ceilingMargin)
        self.loco.boundary = .init(min: SIMD3(-hx, floorMargin, -hz),
                                   max: SIMD3( hx, top,         hz))
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
    /// Which world is being textured — selects the correct wall-photo path (BA396 shared atlas vs
    /// the Art Gallery's per-frame "bake" meshes). Set alongside `root` when the world is built.
    var archetype: WorldArchetype?
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
            // BA396's 6 walls are ONE shared atlas mesh, so re-composite the atlas. The gallery
            // `applyGalleryPhotos` path matches mesh names containing "bake" — BA396 has none, so
            // using it here silently no-ops and the walls stay on the dark build-time placeholders.
            ParametricWorldBuilder.applyBA396Portraits(root, images: images)
        } else {
            ParametricWorldBuilder.applyGalleryPhotos(root, textures: ParametricWorldBuilder.texturesFrom(images))
        }
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

// MARK: - Museum plaque (RealityView attachment)

/// A small museum wall-label shown beside a BA396 portrait. Shows the short `caption`; tapping the
/// header expands the written `narration`. A play button has the shared Curator voice generate a
/// FRESH spoken description for THIS exhibit on demand (`ConversationService.describeExhibit`).
/// Lives inside a `RealityView` attachment, so both taps are ordinary SwiftUI `Button`s — no
/// RealityKit `InputTargetComponent`/`CollisionComponent` plumbing. Styled with the shared Oops
/// glass card so it matches the rest of the flow.
struct BeatPlaqueView: View {
    let node: MuseumNode
    /// The shared Curator voice. nil on the dev/sample path (no story) → play button disabled.
    var convo: ConversationService?
    @State private var expanded = false

    /// This plaque is the one the Curator is currently generating/speaking for (others stay idle).
    private var isThinking: Bool {
        guard let convo, convo.activeBeatID == node.id else { return false }
        return convo.turn == .thinking
    }
    private var isSpeaking: Bool {
        guard let convo, convo.activeBeatID == node.id else { return false }
        return convo.turn == .speaking || convo.isSpeaking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header — tap to expand the written narration.
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            if expanded {
                Text(node.narration)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Play / Stop toggle — first tap has the Curator generate a fresh spoken description for
            // this exhibit; while it plays the button shows a "playing" animation, and tapping it
            // again stops the voice. Pinned to the trailing edge (bottom-right of the plaque).
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    convo?.toggleDescribe(node)
                } label: {
                    HStack(spacing: 10) {
                        if isThinking {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Thinking…").font(.system(size: 18, weight: .semibold))
                        } else if isSpeaking {
                            EqualizerBars()
                            Text("Stop").font(.system(size: 18, weight: .semibold))
                            Image(systemName: "pause.fill").font(.system(size: 16, weight: .bold))
                        } else {
                            Image(systemName: "play.circle.fill").font(.system(size: 22, weight: .semibold))
                            Text("Play").font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(convo == nil ? 0.4 : 0.9))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.white.opacity(isSpeaking ? 0.20 : 0.12), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect()
                .disabled(convo == nil)
                .animation(.easeInOut(duration: 0.2), value: isSpeaking)
                .animation(.easeInOut(duration: 0.2), value: isThinking)
            }
        }
        // Constant width so expanding only grows downward (no left/right shift on tap).
        .frame(width: 420, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 26)
        .oopsCard(cornerRadius: 22)
        .animation(.easeInOut(duration: 0.25), value: expanded)
    }

    /// "ORDEAL · AGE 23" — a quiet exhibit eyebrow above the caption.
    private var stageLabel: String {
        node.stage.replacingOccurrences(of: "_", with: " ").uppercased() + " · AGE \(node.age)"
    }
}

/// A tiny animated equalizer shown on the plaque play button while the Curator is speaking —
/// signals "playing, tap to stop". Three bars bouncing out of phase.
private struct EqualizerBars: View {
    @State private var up = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 4, height: up ? 18 : 6)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14),
                               value: up)
            }
        }
        .frame(height: 20)
        .onAppear { up = true }
    }
}

// MARK: - Plaque previews

/// The plaque WITH a live Curator voice → the play button is enabled ("Play"). Tapping it in the
/// canvas would generate + speak; the preview just shows the resting state.
#Preview("Plaque — play enabled") {
    ZStack {
        Color.black.ignoresSafeArea()
        BeatPlaqueView(node: BeatPlaqueSample.nodes[2], convo: ConversationService())
    }
    .preferredColorScheme(.dark)
}

/// The dev/sample path (no story → no `museumConversation`): the play button is disabled/greyed,
/// matching what "Visit Old World" shows.
#Preview("Plaque — no curator (disabled)") {
    ZStack {
        Color.black.ignoresSafeArea()
        BeatPlaqueView(node: BeatPlaqueSample.nodes[0], convo: nil)
    }
    .preferredColorScheme(.dark)
}
#endif

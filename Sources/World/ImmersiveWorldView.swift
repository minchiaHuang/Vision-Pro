#if os(visionOS)
import SwiftUI
import RealityKit
import UIKit
import GameController
import ARKit
import QuartzCore
import os

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
    /// On-screen / gamepad walking speed inside the parametric gallery, in metres/second.
    /// A brisk walk — tune up for faster exploration, down for a calmer pace.
    static let galleryWalkSpeed: Float = 8.0

    private var loco = SplatLocomotion()
    private weak var root: Entity?
    private var subscription: EventSubscription?

    // Head tracking (for spawn eye-height + diagnostics), mirroring `SplatVisionRenderer`.
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    // TEMP diagnostics — FPS + head height. Remove once perf/eye-height are tuned.
    private static let diag = Logger(subsystem: "VisitingArtisan", category: "GalleryDiag")
    private var fpsAccum: Float = 0
    private var fpsFrames = 0
    private var lastDiagTime: TimeInterval = 0

    func start(root: Entity, span: Float, content: RealityViewContent) {
        self.root = root
        Task { try? await arSession.run([worldTracking]) }
        // User already stands inside the floor-aligned world, so start at the origin
        // (no back-off, unlike the splat path).
        //
        // `SplatLocomotion` derives translation speed as `span · 0.6` m/s — tuned for the large
        // 6DoF splat worlds, where the raw room-sized span (~10 m) gives ~6 m/s and a single hold
        // of ↑ shoots the user out the back wall. We instead want a fixed, comfortable speed
        // independent of room size, so feed a span of `targetWalkSpeed / 0.6` (placement still
        // uses the real bounds). `Self.galleryWalkSpeed` is a brisk ~2.5 m/s — fast enough to
        // explore without feeling sluggish, slow enough to stay controllable. Turn speed
        // (`lookSpeed`) is constant, unaffected.
        self.loco = SplatLocomotion(position: .zero, span: Self.galleryWalkSpeed / 0.6)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self, let root = self.root else { return }
            let gamepad = SplatSpikeDebug.ignoreGamepad ? nil : currentExtendedGamepad()
            // Feed the on-screen hold-to-move pad (`OopsGalleryControls.SplatMovePad` →
            // `SplatManualInput`) alongside the gamepad, mirroring `SplatVisionRenderer`. The
            // snapshot is inert when untouched, so it's safe to always pass — without it the
            // gallery is unwalkable in the Simulator (no controller).
            let manual = SplatManualInput.shared.snapshot()
            self.loco.tick(deltaTime: Float(event.deltaTime), gamepad: gamepad, manual: manual)
            root.transform = Transform(matrix: self.loco.playerTransform().inverse)
            self.logDiagnostics(deltaTime: Float(event.deltaTime))
        }
    }

    /// TEMP: averages FPS and samples the head height once per second. Confirms whether the
    /// Simulator is frame-rate bound (4K textures) and where the device anchor actually sits
    /// (to size the spawn eye-height fix). Remove after tuning.
    private func logDiagnostics(deltaTime dt: Float) {
        if dt > 0 { fpsAccum += 1 / dt; fpsFrames += 1 }
        let now = CACurrentMediaTime()
        guard now - lastDiagTime >= 0.5 else { return }
        let fps = fpsFrames > 0 ? fpsAccum / Float(fpsFrames) : 0
        let head = worldTracking.queryDeviceAnchor(atTimestamp: now)?
            .originFromAnchorTransform.columns.3
        func f(_ v: Float) -> String { String(format: "%.2f", v) }
        let headStr = head.map { "(\(f($0.x)),\(f($0.y)),\(f($0.z)))" } ?? "nil"
        let rootPos = root?.position(relativeTo: nil) ?? .zero
        Self.diag.notice("GALLERY-DIAG fps=\(fps, privacy: .public) head=\(headStr, privacy: .public) root=(\(f(rootPos.x), privacy: .public),\(f(rootPos.y), privacy: .public),\(f(rootPos.z), privacy: .public))")
        fpsAccum = 0; fpsFrames = 0; lastDiagTime = now
    }
}

/// First connected controller's extended gamepad, or nil (same pattern as the splat
/// renderer). Polled per frame on the main actor.
private func currentExtendedGamepad() -> GCExtendedGamepad? {
    GCController.controllers().lazy.compactMap { $0.extendedGamepad }.first
}
#endif

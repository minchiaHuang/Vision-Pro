#if os(visionOS)

import SwiftUI
import CompositorServices
import Metal
import ARKit
import MetalSplatter
import SplatIO
import GameController
import QuartzCore
import simd
import os

/// CompositorServices configuration for the splat immersive space. Matches the
/// iOS splat path's formats so `SplatRenderer` renders identically.
struct SplatLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.depthFormat = .depth32Float
        configuration.colorFormat = .bgra8Unorm_srgb

        let foveationEnabled = capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveationEnabled

        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions = foveationEnabled ? [.foveationEnabled] : []
        let supportedLayouts = capabilities.supportedLayouts(options: options)
        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated
    }
}

/// visionOS walkable Gaussian-splat renderer (the CompositorServices counterpart of
/// the iOS `SplatSpikeRenderer`). Renders a `.spz` per-eye with MetalSplatter, uses
/// ARKit head tracking for the in-cabin 6DoF view, and `SplatLocomotion` (gamepad)
/// for artificial movement through worlds larger than the room.
///
/// `@unchecked Sendable`: `LayerRenderer` access is confined to the render thread,
/// model loading uses async/await, and the locomotion struct is only mutated on the
/// render thread.
final class SplatVisionRenderer: @unchecked Sendable {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VisitingArtisan",
                                    category: "SplatVision")

    private static let maxSimultaneousRenders = 3

    /// Upper bound on rendered splat count. Worlds above this are uniformly downsampled
    /// at load to cap decode time, memory, and per-frame GPU cost on device. A safety
    /// valve independent of the download tier (handles any source, incl. future full_res
    /// or large bundled assets). ~1.5M is comfortable on Vision Pro; tune on device.
    private static let maxSplatPoints = 1_500_000

    private let layerRenderer: LayerRenderer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let splatURL: URL
    /// Raw marble/World Labs exports load upside-down; flip them upright at framing.
    private let flipUpsideDown: Bool

    private let inFlight = DispatchSemaphore(value: maxSimultaneousRenders)

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    /// Nil on the visionOS Simulator (`HandTrackingProvider.isSupported == false` there);
    /// gesture manipulation then comes only from the on-screen debug pad.
    private let handTracking: HandTrackingProvider? =
        HandTrackingProvider.isSupported ? HandTrackingProvider() : nil

    /// Result of an off-thread load, handed to the render thread exactly once.
    private struct LoadedScene {
        let splat: SplatRenderer
        let calibration: simd_float4x4
        let initialLocomotion: SplatLocomotion
        /// World placement (calibrated space) for the in-world USDZ model, if any.
        let modelPlacement: simd_float4x4
    }
    /// Published by `load()` under `loadLock`; the render thread adopts it once (then
    /// owns the copies below outright), so `splat`/`locomotion` never race.
    private let loadLock = NSLock()
    private var pendingScene: LoadedScene?

    // Render-thread-owned (mutated/read only inside the render loop after adoption).
    private var splat: SplatRenderer?
    private var sceneCalibration: simd_float4x4 = matrix_identity_float4x4
    private var locomotion = SplatLocomotion()
    private var lastTickTime: CFTimeInterval?
    /// Edge-trigger state for the gamepad exit button (☰); see `renderFrame`.
    private var exitButtonWasPressed = false

    /// USDZ overlay engine compositing this world's fixed-placement objects into the splat
    /// scene. Nil if the pipeline failed to build. Objects are placed at authored positions
    /// (see `SplatObject`) and stay put — the whole-group gesture was removed in Iteration B.
    private let meshRenderer: SplatMeshRenderer?

    /// Fallback model when a world ships no object list (legacy single-demo behaviour).
    private static let demoModelName = "hummingbird_anim"

    init(layerRenderer: LayerRenderer, splatURL: URL, flipUpsideDown: Bool, objects: [SplatObject] = []) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        self.commandQueue = device.makeCommandQueue()!
        self.splatURL = splatURL
        self.flipUpsideDown = flipUpsideDown

        // Build the mesh overlay pipeline up front; load this world's objects off-thread at
        // their authored placements. Empty list → fall back to the single demo model at the
        // centre. Use error-level logs (persisted) so failures are visible in `log show`.
        do {
            let mr = try SplatMeshRenderer(device: device,
                                           colorFormat: layerRenderer.configuration.colorFormat,
                                           depthFormat: layerRenderer.configuration.depthFormat)
            self.meshRenderer = mr
            let placed = objects.isEmpty ? [SplatObject(Self.demoModelName)] : objects
            for obj in placed {
                if let url = Bundle.main.url(forResource: obj.name, withExtension: "usdz") {
                    let offset = Self.translation(obj.position.x, obj.position.y, obj.position.z)
                        * Self.rotationY(obj.yawDegrees * .pi / 180)
                        * Self.uniformScale(obj.scale)
                    Self.log.notice("MESH: loading \(obj.name).usdz @ \(obj.position)")
                    mr.loadModel(url: url, offset: offset)
                } else {
                    Self.log.error("MESH: \(obj.name).usdz NOT in bundle")
                }
            }
        } catch {
            self.meshRenderer = nil
            Self.log.error("MESH: pipeline build FAILED: \(error.localizedDescription)")
        }
    }

    /// Entry point used by the `CompositorLayer` closure. The render loop starts
    /// immediately (presenting cleared frames so the immersive space is never black /
    /// frozen) while the splat loads off-thread; the loop adopts it when ready.
    static func startRendering(_ layerRenderer: LayerRenderer, splatURL: URL, flipUpsideDown: Bool, objects: [SplatObject] = []) {
        let renderer = SplatVisionRenderer(layerRenderer: layerRenderer, splatURL: splatURL, flipUpsideDown: flipUpsideDown, objects: objects)

        // Load off the render thread; publishes a LoadedScene when done.
        Task.detached(priority: .userInitiated) {
            do {
                try await renderer.load()
            } catch {
                log.error("Failed to load splat: \(error.localizedDescription)")
                await SplatSession.shared.fail(error.localizedDescription)
            }
        }

        // ARKit + render loop on the dedicated render-priority executor.
        Task(executorPreference: SplatRenderExecutor.shared) {
            // Hand tracking (device only) drives the in-world model's rotate/scale gesture.
            var providers: [any DataProvider] = [renderer.worldTracking]
            if let handTracking = renderer.handTracking {
                _ = await renderer.arSession.requestAuthorization(for: [.handTracking])
                providers.append(handTracking)
            }
            do {
                try await renderer.arSession.run(providers)
            } catch {
                log.error("Failed to start ARKit session: \(error.localizedDescription)")
            }
            if let handTracking = renderer.handTracking {
                renderer.startHandGestureTask(handTracking)
            }
            renderer.renderLoop()
        }
    }

    /// Consumes hand-anchor updates and feeds the two-hand pinch gesture into the shared
    /// manipulation sink (the render loop applies it). Device only — `handTracking` is nil
    /// in the Simulator, so this is never started there.
    private func startHandGestureTask(_ handTracking: HandTrackingProvider) {
        let processor = SplatHandGestureProcessor()
        Task.detached(priority: .userInitiated) {
            for await update in handTracking.anchorUpdates {
                if let delta = processor.process(anchor: update.anchor) {
                    SplatModelManipulation.shared.add(yaw: delta.yaw, scaleMul: delta.scaleMul)
                }
            }
        }
    }

    // MARK: - Loading

    private func load() async throws {
        await SplatSession.shared.beginLoading()
        await SplatSession.shared.setPreparing()

        let localURL = splatURL.isFileURL ? splatURL : try await SplatDownloader.fetch(splatURL)

        let renderer = try SplatRenderer(device: device,
                                         colorFormat: layerRenderer.configuration.colorFormat,
                                         depthFormat: layerRenderer.configuration.depthFormat,
                                         sampleCount: 1,
                                         maxViewCount: layerRenderer.properties.viewCount,
                                         maxSimultaneousRenders: Self.maxSimultaneousRenders)

        // Fast path: load pre-decoded GPU data from disk cache (skips 30 s readAll).
        if let cached = try? SplatCache.loadScene(for: localURL, flipUpsideDown: flipUpsideDown) {
            do {
                let splatBuf = try MetalBuffer<EncodedSplatPoint>(device: device,
                                                                  capacity: cached.pointCount)
                cached.splatData.withUnsafeBytes { ptr in
                    guard let src = ptr.baseAddress else { return }
                    memcpy(splatBuf.values, src, cached.splatData.count)
                }
                splatBuf.count = cached.pointCount

                var shBuf: MetalBuffer<Float16>?
                if !cached.shData.isEmpty {
                    let shCount = cached.shData.count / MemoryLayout<Float16>.stride
                    let buf = try MetalBuffer<Float16>(device: device, capacity: shCount)
                    cached.shData.withUnsafeBytes { ptr in
                        guard let src = ptr.baseAddress else { return }
                        memcpy(buf.values, src, cached.shData.count)
                    }
                    buf.count = shCount
                    shBuf = buf
                }

                let chunk = SplatChunk(splats: splatBuf, shCoefficients: shBuf,
                                       shDegree: cached.shDegree)
                _ = await renderer.addChunk(chunk)
                let locomotion = SplatLocomotion(position: cached.locomotionPosition,
                                                 span: cached.locomotionSpan)
                loadLock.withLock {
                    pendingScene = LoadedScene(splat: renderer,
                                              calibration: cached.calibration,
                                              initialLocomotion: locomotion,
                                              modelPlacement: cached.modelPlacement)
                }
                await SplatSession.shared.setReady()
                Self.log.info("SplatCache hit: \(cached.pointCount) pts")
                return
            } catch {
                Self.log.warning("SplatCache load failed, falling back to decode: \(error)")
            }
        }

        // Slow path: full zstd decode (first entry or cache miss).
        let rawPoints = try await AutodetectSceneReader(localURL).readAll()
        guard !rawPoints.isEmpty else {
            Self.log.error("Splat decoded to 0 points")
            await SplatSession.shared.fail("World decoded to 0 points.")
            return
        }

        let points = Self.downsample(rawPoints, to: Self.maxSplatPoints)
        let (calibration, initialLocomotion, modelPlacement) = Self.framing(points,
                                                                             flipUpsideDown: flipUpsideDown)
        let chunk = try SplatChunk(device: device, from: points)
        _ = await renderer.addChunk(chunk)

        // Persist to cache in background so the next entry is fast.
        let urlForSave = localURL
        let flip = flipUpsideDown
        Task.detached(priority: .background) {
            try? SplatCache.saveScene(chunk: chunk,
                                      calibration: calibration,
                                      locomotionPosition: initialLocomotion.position,
                                      locomotionSpan: initialLocomotion.span,
                                      modelPlacement: modelPlacement,
                                      for: urlForSave,
                                      flipUpsideDown: flip)
        }

        loadLock.withLock {
            pendingScene = LoadedScene(splat: renderer,
                                       calibration: calibration,
                                       initialLocomotion: initialLocomotion,
                                       modelPlacement: modelPlacement)
        }
        await SplatSession.shared.setReady()
        Self.log.info("Loaded splat: \(rawPoints.count) pts → \(points.count) after cap")
    }

    /// Uniformly strides a point cloud down to at most `budget` points. Returns the
    /// input unchanged when already within budget (e.g. the bundled 100k asset).
    private static func downsample(_ points: [SplatPoint], to budget: Int) -> [SplatPoint] {
        guard points.count > budget else { return points }
        let stride = Int((Double(points.count) / Double(budget)).rounded(.up))
        var out = [SplatPoint]()
        out.reserveCapacity(points.count / stride + 1)
        var i = 0
        while i < points.count { out.append(points[i]); i += stride }
        return out
    }

    /// Centroid recentre + mean radius → scene calibration and the start viewpoint.
    /// The user begins backed off along +Z (the proven iOS framing) and walks in.
    /// Pure (no `self` mutation) so it can run on the load thread before handoff.
    static func framing(_ points: [SplatPoint],
                        flipUpsideDown: Bool) -> (calibration: simd_float4x4,
                                                  locomotion: SplatLocomotion,
                                                  modelPlacement: simd_float4x4) {
        var sum = SIMD3<Float>.zero
        for p in points { sum += p.position }
        let center = sum / Float(points.count)

        var distSum: Float = 0
        for p in points { distSum += simd_length(p.position - center) }
        let meanRadius = max(distSum / Float(points.count), 0.001)

        // Recentre on the centroid; for upside-down exports, also rotate the world
        // 180° about X (recentre first, then flip about the origin).
        var calibration = translation(-center.x, -center.y, -center.z)
        if flipUpsideDown { calibration = rotationX180() * calibration }
        // Spawn at the world CENTRE (the centroid = origin in calibrated space) so the user
        // begins inside the scene rather than backed off outside it. `span` still scales
        // movement speed by the scene size. (Y stays 0 = centroid height; tune on device.)
        let locomotion = SplatLocomotion(position: SIMD3(0, 0, 0),
                                         span: max(meanRadius, 1))

        // Object group anchor = the world centre (identity). Each object carries its own
        // absolute centre-relative placement (see `SplatObject`), so they encircle the spawn.
        let modelPlacement = matrix_identity_float4x4
        return (calibration, locomotion, modelPlacement)
    }

    // MARK: - Per-frame viewports (locomotion + head tracking)

    private func viewports(drawable: LayerRenderer.Drawable,
                           deviceAnchor: DeviceAnchor?) -> [SplatRenderer.ViewportDescriptor] {
        let playerWorld = locomotion.playerTransform()
        let originFromDevice = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        return drawable.views.enumerated().map { index, view in
            // Eye world transform = player vehicle · head pose · per-eye offset.
            let cameraWorld = playerWorld * originFromDevice * view.transform
            let viewMatrix = cameraWorld.inverse * sceneCalibration
            let projectionMatrix = drawable.computeProjection(viewIndex: index)
            let vp = view.textureMap.viewport
            return SplatRenderer.ViewportDescriptor(
                viewport: vp,
                projectionMatrix: projectionMatrix,
                viewMatrix: viewMatrix,
                screenSize: SIMD2(Int(vp.width), Int(vp.height)))
        }
    }

    // MARK: - Render loop

    private func renderFrame() {
        guard let frame = layerRenderer.queryNextFrame() else { return }

        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        let drawables = frame.queryDrawables()
        guard !drawables.isEmpty else { return }

        // Adopt the loaded scene once it's published (render thread takes ownership).
        if splat == nil {
            loadLock.lock()
            let scene = pendingScene
            loadLock.unlock()
            if let scene {
                splat = scene.splat
                sceneCalibration = scene.calibration
                locomotion = scene.initialLocomotion
                // The objects live in world space; the per-eye viewMatrix already folds in
                // sceneCalibration, so the mesh renderer cancels it back out (otherwise the
                // objects get calibrated twice — flipped + offset by the centroid). The
                // framing placement is the group anchor the objects ring around.
                meshRenderer?.anchor = scene.modelPlacement
                meshRenderer?.sceneCalibrationInverse = scene.calibration.inverse
            }
        }

        // Not ready: still complete the frame lifecycle with empty command buffers,
        // or CompositorServices crashes with "too many frames in flight".
        guard let splat, splat.isReadyToRender else {
            frame.startSubmission()
            for drawable in drawables {
                guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }
                drawable.encodePresent(commandBuffer: commandBuffer)
                commandBuffer.commit()
            }
            frame.endSubmission()
            return
        }

        _ = inFlight.wait(timeout: .distantFuture)
        frame.startSubmission()

        // Advance locomotion once per frame (gamepad polled directly; thread-safe reads).
        let now = CACurrentMediaTime()
        let dt = Float(now - (lastTickTime ?? now))
        lastTickTime = now
        let gamepad = SplatSpikeDebug.ignoreGamepad ? nil : Self.currentGamepad()

        // No-controller fallback (Simulator + device): on-screen hold-to-move pad. Inert
        // when untouched, so it's safe to always feed alongside the gamepad. (Keyboard
        // input is intentionally not read: the visionOS Simulator captures WASD/QE/arrows
        // to move the simulated device, so the app never receives them.)
        let manual = SplatManualInput.shared.snapshot()
        locomotion.tick(deltaTime: dt, gamepad: gamepad, manual: manual)

        // Iteration B: objects are FIXED at their authored placements — the whole-group
        // rotate/scale gesture was removed, so `groupTransform` stays identity here.
        // TODO(phase3): per-object selection — route the two-hand gesture to a single picked
        // object (gaze/point selection + a per-object transform) instead of the whole cluster.

        // Leave the world, edge-triggered: gamepad ☰ (Menu/Options). The mouse / gaze-tap
        // "Leave world" button in the controls window is the primary exit; the gamepad ☰ is
        // routed here (via the shared session, which owns `dismissImmersiveSpace`) so a
        // controller user can exit no matter how far they've walked.
        let exitPressed = gamepad?.buttonMenu.isPressed ?? false
        if exitPressed && !exitButtonWasPressed {
            Task { @MainActor in SplatSession.shared.requestExit() }
        }
        exitButtonWasPressed = exitPressed

        let primaryDrawable = drawables[0]
        let time = LayerRenderer.Clock.Instant.epoch
            .duration(to: primaryDrawable.frameTiming.presentationTime).timeInterval
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)

        let layered = layerRenderer.configuration.layout == .layered

        for (index, drawable) in drawables.enumerated() {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }
            drawable.deviceAnchor = deviceAnchor

            if index == drawables.count - 1 {
                let semaphore = inFlight
                commandBuffer.addCompletedHandler { _ in semaphore.signal() }
            }

            let vps = viewports(drawable: drawable, deviceAnchor: deviceAnchor)
            let arrayLength = layered ? drawable.views.count : 1
            do {
                _ = try splat.render(viewports: vps,
                                     colorTexture: drawable.colorTextures[0],
                                     colorStoreAction: .store,
                                     depthTexture: drawable.depthTextures[0],
                                     rasterizationRateMap: drawable.rasterizationRateMaps.first,
                                     renderTargetArrayLength: arrayLength,
                                     to: commandBuffer)
            } catch {
                Self.log.error("Render failed: \(error.localizedDescription)")
            }

            // Composite the in-world USDZ model on top of the splat frame (own render
            // pass that LOADs the splat color + depth, so the two occlude correctly).
            meshRenderer?.encode(into: commandBuffer,
                                 colorTexture: drawable.colorTextures[0],
                                 depthTexture: drawable.depthTextures[0],
                                 rasterizationRateMap: drawable.rasterizationRateMaps.first,
                                 renderTargetArrayLength: arrayLength,
                                 viewports: vps)

            drawable.encodePresent(commandBuffer: commandBuffer)
            commandBuffer.commit()
        }

        frame.endSubmission()
    }

    private func renderLoop() {
        while true {
            autoreleasepool {
                switch layerRenderer.state {
                case .invalidated:
                    Self.log.warning("Layer invalidated")
                case .paused:
                    layerRenderer.waitUntilRunning()
                default:
                    renderFrame()
                }
            }
            if layerRenderer.state == .invalidated {
                arSession.stop()
                return
            }
        }
    }

    // MARK: - Helpers

    /// First connected controller's extended gamepad, or nil. Polled per frame; the
    /// GameController value reads are safe off the main thread.
    private static func currentGamepad() -> GCExtendedGamepad? {
        GCController.controllers().lazy.compactMap { $0.extendedGamepad }.first
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(x, y, z, 1)))
    }

    /// 180° rotation about X (Y→-Y, Z→-Z): rights raw World Labs/marble exports that
    /// load upside-down. A proper rotation (det +1), so it doesn't mirror the splats.
    private static func rotationX180() -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, -1, 0, 0),
            SIMD4(0, 0, -1, 0),
            SIMD4(0, 0, 0, 1)))
    }

    /// Rotation about +Y by `radians`; used to spin the in-world model via hand gestures.
    private static func rotationY(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians), s = sin(radians)
        return simd_float4x4(columns: (
            SIMD4( c, 0, -s, 0),
            SIMD4( 0, 1,  0, 0),
            SIMD4( s, 0,  c, 0),
            SIMD4( 0, 0,  0, 1)))
    }

    /// Uniform scale; used to grow/shrink the in-world model via hand gestures.
    private static func uniformScale(_ s: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(s, 0, 0, 0),
            SIMD4(0, s, 0, 0),
            SIMD4(0, 0, s, 0),
            SIMD4(0, 0, 0, 1)))
    }
}

/// Dedicated render-priority executor so the render loop runs off the main actor.
final class SplatRenderExecutor: TaskExecutor {
    static let shared = SplatRenderExecutor()
    private let queue = DispatchQueue(label: "SplatRenderThread", qos: .userInteractive)

    func enqueue(_ job: UnownedJob) {
        queue.async { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
    }

    func asUnownedSerialExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}

/// Helper mirroring the iOS renderer's `LayerRenderer.Clock.Instant.Duration` → seconds.
private extension LayerRenderer.Clock.Instant.Duration {
    var timeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}

#endif // os(visionOS)

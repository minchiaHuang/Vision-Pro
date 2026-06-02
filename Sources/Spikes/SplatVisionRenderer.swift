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

    private let layerRenderer: LayerRenderer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let splatURL: URL

    private var splat: SplatRenderer?
    private let inFlight = DispatchSemaphore(value: maxSimultaneousRenders)

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    /// Recentres raw splat-world coordinates to the origin (same role as the iOS
    /// renderer's `sceneCalibration`). World Labs `.spz` is Y-up, so this is a pure
    /// translation — no flip.
    private var sceneCalibration: simd_float4x4 = matrix_identity_float4x4
    private var locomotion = SplatLocomotion()
    private var lastTickTime: CFTimeInterval?

    init(layerRenderer: LayerRenderer, splatURL: URL) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        self.commandQueue = device.makeCommandQueue()!
        self.splatURL = splatURL
    }

    /// Entry point used by the `CompositorLayer` closure: load the model, then drive
    /// the render loop on a dedicated render-priority executor.
    static func startRendering(_ layerRenderer: LayerRenderer, splatURL: URL) {
        let renderer = SplatVisionRenderer(layerRenderer: layerRenderer, splatURL: splatURL)
        Task(executorPreference: SplatRenderExecutor.shared) {
            do {
                try await renderer.load()
            } catch {
                log.error("Failed to load splat: \(error.localizedDescription)")
            }
            do {
                try await renderer.arSession.run([renderer.worldTracking])
            } catch {
                log.error("Failed to start ARKit session: \(error.localizedDescription)")
            }
            renderer.renderLoop()
        }
    }

    // MARK: - Loading

    private func load() async throws {
        // Remote World Labs URLs are downloaded + cached; bundled/local files read directly.
        let localURL = splatURL.isFileURL ? splatURL : try await SplatDownloader.fetch(splatURL)

        let renderer = try SplatRenderer(device: device,
                                         colorFormat: layerRenderer.configuration.colorFormat,
                                         depthFormat: layerRenderer.configuration.depthFormat,
                                         sampleCount: 1,
                                         maxViewCount: layerRenderer.properties.viewCount,
                                         maxSimultaneousRenders: Self.maxSimultaneousRenders)
        let points = try await AutodetectSceneReader(localURL).readAll()
        guard !points.isEmpty else {
            Self.log.error("Splat decoded to 0 points")
            return
        }
        frameScene(points)
        let chunk = try SplatChunk(device: device, from: points)
        _ = await renderer.addChunk(chunk)
        self.splat = renderer
        Self.log.info("Loaded \(points.count) splats")
    }

    /// Centroid recentre + mean radius → scene calibration and the start viewpoint.
    /// The user begins backed off along +Z (the proven iOS framing) and walks in.
    private func frameScene(_ points: [SplatPoint]) {
        var sum = SIMD3<Float>.zero
        for p in points { sum += p.position }
        let center = sum / Float(points.count)

        var distSum: Float = 0
        for p in points { distSum += simd_length(p.position - center) }
        let meanRadius = max(distSum / Float(points.count), 0.001)

        sceneCalibration = Self.translation(-center.x, -center.y, -center.z)
        let frameDistance = meanRadius * 3
        locomotion = SplatLocomotion(position: SIMD3(0, 0, frameDistance), span: max(meanRadius, 1))
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
        locomotion.tick(deltaTime: dt, gamepad: gamepad)

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

            do {
                _ = try splat.render(viewports: viewports(drawable: drawable, deviceAnchor: deviceAnchor),
                                     colorTexture: drawable.colorTextures[0],
                                     colorStoreAction: .store,
                                     depthTexture: drawable.depthTextures[0],
                                     rasterizationRateMap: drawable.rasterizationRateMaps.first,
                                     renderTargetArrayLength: layered ? drawable.views.count : 1,
                                     to: commandBuffer)
            } catch {
                Self.log.error("Render failed: \(error.localizedDescription)")
            }

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

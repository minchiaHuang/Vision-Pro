import SwiftUI

// ⚠️ DEV / SPIKE ONLY — do NOT ship.
// Phase 2: render a World Labs Gaussian-splat (.spz) with MetalSplatter and let
// the user walk around it (6DoF) via touch + PS5 controller. When `launchIntoSpike`
// is true the app boots straight into the splat viewer, bypassing the normal flow.
enum SplatSpikeDebug {
    static let launchIntoSpike = false

    /// Bundled spike asset (file name without extension). Downloaded from the
    /// existing world a236ea24 (500k variant). Spike-only; not a shipping asset.
    static let bundledSplat = "world_a236ea24_100k"

    /// The iOS Simulator can report a phantom game controller whose resting axes
    /// drive the camera out of the scene. Set true to ignore the gamepad and test
    /// touch-only in the Simulator. Keep false on device (real controller works).
    static let ignoreGamepad = false
}

#if !os(visionOS)
import MetalKit
import Metal
import simd
import MetalSplatter
import SplatIO
import os

/// Walkable splat viewer for a local `.spz` file. Owns the `WorldCameraRig` and
/// `GamepadManager` so touch gestures and the renderer's per-frame gamepad poll
/// mutate the same first-person rig (same pattern as `USDZTestView`).
struct SplatSceneView: View {
    let splatFileURL: URL

    @State private var rig = WorldCameraRig()
    @State private var gamepad = GamepadManager()
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SplatMetalView(rig: rig, gamepad: gamepad, splatFileURL: splatFileURL)
                .ignoresSafeArea()
                .gesture(lookGesture)
                .simultaneousGesture(dollyGesture)
            overlay
        }
    }

    private var lookGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                rig.look(deltaX: Float(value.translation.width - lastDrag.width),
                         deltaY: Float(value.translation.height - lastDrag.height))
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var dollyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                rig.dolly(delta: Float(value.magnification - lastMagnification))
                lastMagnification = value.magnification
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            HStack {
                if gamepad.isConnected {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            Text(gamepad.isConnected
                 ? "Left stick move · right stick look · R2/L2 up/down · ○ reset"
                 : "Drag to look · pinch to move")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 20)
        }
    }
}

/// DEV-only standalone entry (`SplatSpikeDebug.launchIntoSpike`) — renders the
/// bundled spike asset. The real app reaches walkable worlds via `SplatWorldView`.
struct SplatSpikeView: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: SplatSpikeDebug.bundledSplat, withExtension: "spz") {
            SplatSceneView(splatFileURL: url)
        } else {
            Text("Bundled \(SplatSpikeDebug.bundledSplat).spz not found").padding()
        }
    }
}

/// Downloads a World Labs `.spz` from its public CDN URL (reusing a prior download
/// in the caches dir), then shows the walkable scene. Used by the world phase when
/// the user switches to "walkable".
struct SplatWorldView: View {
    let remoteURL: URL

    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let localURL {
                SplatSceneView(splatFileURL: localURL)
            } else if failed {
                Text("Couldn't load the walkable world.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Loading walkable world…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .task(id: remoteURL) {
            do { localURL = try await SplatDownloader.fetch(remoteURL) }
            catch { failed = true }
        }
    }
}

/// Caches a downloaded `.spz` so re-entering "walkable" doesn't re-download.
enum SplatDownloader {
    static func fetch(_ remote: URL) async throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dest = caches.appendingPathComponent("worldlabs-\(remote.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let (tmp, response) = try await URLSession.shared.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

/// Bridges an `MTKView` + `SplatSpikeRenderer` into SwiftUI.
private struct SplatMetalView: UIViewRepresentable {
    let rig: WorldCameraRig
    let gamepad: GamepadManager
    let splatFileURL: URL

    func makeCoordinator() -> SplatSpikeRenderer {
        SplatSpikeRenderer(rig: rig, gamepad: gamepad, splatFileURL: splatFileURL)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

/// Loads the bundled `.spz` into a `SplatRenderer` and draws it each frame using a
/// `WorldCameraRig`-driven view matrix, so touch / gamepad input moves the camera
/// through the scene (6DoF) instead of an automatic orbit.
@MainActor
final class SplatSpikeRenderer: NSObject, MTKViewDelegate {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VisitingArtisan",
                                    category: "SplatSpike")

    private let maxSimultaneousRenders = 3
    private let fovyRadians: Float = 65 * .pi / 180

    private let rig: WorldCameraRig
    private let gamepad: GamepadManager
    private let splatFileURL: URL

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var splat: SplatRenderer?
    private var inFlight: DispatchSemaphore!

    /// Maps raw splat-world coordinates → origin-centred space the rig drives in.
    /// World Labs `.spz` is already Y-up, so this is just a recentre (no flip).
    private var sceneCalibration: simd_float4x4 = matrix_identity_float4x4
    private var nearZ: Float = 0.05
    private var farZ: Float = 200
    private var frameDistance: Float = 4

    private var lastTimestamp: CFTimeInterval?
    private var drawableSize: CGSize = .zero

    init(rig: WorldCameraRig, gamepad: GamepadManager, splatFileURL: URL) {
        self.rig = rig
        self.gamepad = gamepad
        self.splatFileURL = splatFileURL
        super.init()
    }

    func configure(_ view: MTKView) {
        guard let device = view.device else {
            Self.log.error("No Metal device")
            return
        }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.inFlight = DispatchSemaphore(value: maxSimultaneousRenders)

        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = self
        drawableSize = view.drawableSize

        Task { await load() }
    }

    private func load() async {
        let url = splatFileURL
        do {
            let renderer = try SplatRenderer(device: device,
                                             colorFormat: .bgra8Unorm_srgb,
                                             depthFormat: .depth32Float,
                                             sampleCount: 1,
                                             maxViewCount: 1,
                                             maxSimultaneousRenders: maxSimultaneousRenders)
            let points = try await AutodetectSceneReader(url).readAll()
            guard !points.isEmpty else {
                Self.log.error("Splat file decoded to 0 points")
                return
            }
            await frameScene(points)
            let chunk = try SplatChunk(device: device, from: points)
            _ = await renderer.addChunk(chunk)
            self.splat = renderer
            Self.log.info("Loaded \(points.count) splats")
        } catch {
            Self.log.error("Failed to load splat: \(error.localizedDescription)")
        }
    }

    /// Centroid + mean radius → scene calibration (recentre + upright flip), clip
    /// planes, and rig movement scale. The rig starts at the capture point (origin
    /// of the calibrated space) so the user stands inside the world.
    private func frameScene(_ points: [SplatPoint]) async {
        // Centroid + mean radius are O(n) over the full point cloud (100k+ points).
        // Run the loops off the main actor so a large splat doesn't freeze the UI.
        let (center, meanRadius) = await Task.detached(priority: .userInitiated) {
            var sum = SIMD3<Float>.zero
            for p in points { sum += p.position }
            let center = sum / Float(points.count)

            var distSum: Float = 0
            for p in points { distSum += simd_length(p.position - center) }
            return (center, max(distSum / Float(points.count), 0.001))
        }.value

        sceneCalibration = translation(-center.x, -center.y, -center.z)
        frameDistance = meanRadius * 3
        nearZ = max(0.02, meanRadius * 0.01)
        farZ = (frameDistance + meanRadius) * 3 + 100
        // Start backed off along +Z looking at the recentred scene (the proven
        // Stage-B framing), then the user walks forward (-Z) into the world.
        rig.configure(position: SIMD3(0, 0, frameDistance), span: max(meanRadius, 1))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }

    func draw(in view: MTKView) {
        guard let splat, splat.isReadyToRender,
              let drawable = view.currentDrawable,
              drawableSize.width > 0, drawableSize.height > 0 else { return }

        inFlight.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore?.signal() }

        // Advance camera from input (gamepad polled here; touch mutates rig directly).
        let now = CACurrentMediaTime()
        let dt = Float(now - (lastTimestamp ?? now))
        lastTimestamp = now
        rig.tick(deltaTime: dt, gamepad: SplatSpikeDebug.ignoreGamepad ? nil : gamepad.gamepad)

        let viewMatrix = rig.viewMatrix() * sceneCalibration
        let viewport = SplatRenderer.ViewportDescriptor(
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: drawableSize.width, height: drawableSize.height,
                                  znear: 0, zfar: 1),
            projectionMatrix: perspectiveRH(fovy: fovyRadians,
                                            aspect: Float(drawableSize.width / drawableSize.height),
                                            nearZ: nearZ, farZ: farZ),
            viewMatrix: viewMatrix,
            screenSize: SIMD2(Int(drawableSize.width), Int(drawableSize.height)))

        var didRender = false
        do {
            didRender = try splat.render(viewports: [viewport],
                                         colorTexture: drawable.texture,
                                         colorStoreAction: .store,
                                         depthTexture: view.depthStencilTexture,
                                         rasterizationRateMap: nil,
                                         renderTargetArrayLength: 0,
                                         to: commandBuffer)
        } catch {
            Self.log.error("Render failed: \(error.localizedDescription)")
        }

        if didRender { commandBuffer.present(drawable) }
        commandBuffer.commit()
    }
}

// MARK: - Matrix helpers (right-handed, Metal NDC z ∈ [0,1])

private func perspectiveRH(fovy: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspect
    let zs = farZ / (nearZ - farZ)
    return simd_float4x4(columns: (
        SIMD4(xs, 0, 0, 0),
        SIMD4(0, ys, 0, 0),
        SIMD4(0, 0, zs, -1),
        SIMD4(0, 0, zs * nearZ, 0)
    ))
}

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(x, y, z, 1)
    ))
}

#else

/// Splat rendering is iOS/iPadOS-only in this spike (visionOS uses a different
/// CompositorLayer path — deferred). Placeholder so the debug flag compiles everywhere.
struct SplatSpikeView: View {
    var body: some View {
        Text("Splat spike runs on iOS/iPadOS only.")
            .padding()
    }
}

#endif

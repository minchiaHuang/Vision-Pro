#if os(visionOS)
import SwiftUI
import RealityKit
import GameController
import SplatIO
import simd

// SPIKE — Phase 1 of the "head-locked control HUD" plan.
//
// Goal of this step: prove that a SwiftUI control bar can be pinned to the RIGHT of the
// user's view and follow their head inside a RealityKit `RealityView` immersive space —
// the mechanism the real feature needs and which a CompositorServices/`CompositorLayer`
// world (the current splat path) cannot provide.
//
// This step deliberately uses a PLACEHOLDER background (skybox + parallax cubes), so the
// head-follow HUD can be validated in isolation before the harder Gaussian-splat geometry
// (LowLevelMesh) lands in the next step. Reached from the Dev Menu → "Splat RK (HUD spike)".

/// The immersive space content: a placeholder world + a head-anchored HUD attachment.
struct SplatRKImmersiveView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    /// Guards the exit so taps can't double-fire a dismiss.
    @State private var isExiting = false
    /// Per-frame artificial locomotion (move pad / gamepad), retained across updates.
    @State private var locomotor = RKSpikeLocomotor()

    var body: some View {
        RealityView { content, attachments in
            // Skybox stays fixed around the user (not walked through).
            content.add(Self.makeSky())

            // The walkable content lives under a root the locomotor moves each frame
            // (player walks → world shifts opposite); head tracking adds local 6DoF on top.
            // Load the real splat as RealityKit geometry; fall back to placeholder cubes if
            // the asset is missing or the mesh fails to build.
            let root = Entity()
            let loco: SplatLocomotion
            if let built = await Self.buildSplatWorld() {
                root.addChild(built.content)
                loco = built.loco
            } else {
                root.addChild(Self.makeCubesRoot())
                loco = SplatLocomotion(position: .zero, span: 6)
            }
            content.add(root)
            locomotor.start(loco: loco, root: root, content: content)

            // Head-anchored controls: ride with the head pose. HUD on the right, the
            // hold-to-move pad on the lower-left (mirrors a controller: move left / act right).
            let head = AnchorEntity(.head)
            if let hud = attachments.entity(for: "hud") {
                hud.position = [0.42, -0.05, -0.85]   // +x right · -y down · -z forward (m)
                head.addChild(hud)
            }
            if let move = attachments.entity(for: "move") {
                move.position = [-0.42, -0.12, -0.85] // -x left
                head.addChild(move)
            }
            content.add(head)
        } attachments: {
            Attachment(id: "hud") {
                SplatRKHUD(onPrev: { exit() }, onExit: { exit() })
            }
            Attachment(id: "move") {
                RKMovePad()
            }
        }
    }

    private func exit() {
        guard !isExiting else { return }
        isExiting = true
        SplatManualInput.shared.reset()
        Task { await dismissImmersiveSpace() }
    }

    /// Fixed dark skybox so we're "inside" something while walking.
    private static func makeSky() -> Entity {
        let sky = ModelEntity(mesh: .generateSphere(radius: 14),
                              materials: [UnlitMaterial(color: .init(white: 0.06, alpha: 1))])
        sky.scale = [-1, 1, 1]   // inside-out
        return sky
    }

    /// Placeholder walkable content: concentric rings of colored cubes spread over ~9 m so
    /// artificial locomotion (walking past them) is obvious. Replaced by the real splat
    /// cloud in Step 2.
    private static func makeCubesRoot() -> Entity {
        let root = Entity()
        var i = 0
        for ring in stride(from: Float(1.5), through: 9, by: 1.5) {
            let count = max(6, Int(ring * 3))
            for k in 0..<count {
                let a = Float(k) / Float(count) * 2 * .pi
                let color = UIColor(hue: CGFloat(i % 12) / 12, saturation: 0.7, brightness: 0.9, alpha: 1)
                let cube = ModelEntity(mesh: .generateBox(size: 0.3),
                                       materials: [SimpleMaterial(color: color, isMetallic: false)])
                cube.position = [cos(a) * ring, Float(i % 5) * 0.3 - 0.6, sin(a) * ring]
                root.addChild(cube)
                i += 1
            }
        }
        return root
    }

    // MARK: - Splat → RealityKit geometry (Step 2)

    /// Upper bound on splats for this spike. Each splat becomes a 4-vertex quad, so this is
    /// 4× vertices. Kept modest for a first RealityView pass; tune on device.
    private static let maxSplats = 120_000

    /// Loads the bundled `.spz`, frames it, and builds a colored-quad mesh + its calibration
    /// transform. Returns the content entity (calibration → model) and the start locomotion.
    static func buildSplatWorld() async -> (content: Entity, loco: SplatLocomotion)? {
        guard let url = Bundle.main.url(forResource: "vibrant_loft_art_studio", withExtension: "spz"),
              let raw = try? await AutodetectSceneReader(url).readAll(), !raw.isEmpty
        else { return nil }

        let points = downsample(raw, to: maxSplats)
        let (calibration, loco) = framing(points, flipUpsideDown: true)

        guard let (mesh, texture) = try? await buildSplatMesh(points) else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .none   // quads are single-sided; show both faces
        let model = ModelEntity(mesh: mesh, materials: [material])

        let calib = Entity()
        calib.transform = Transform(matrix: calibration)
        calib.addChild(model)
        return (calib, loco)
    }

    /// Builds a mesh of one camera-independent oriented quad per splat (positioned/rotated/
    /// scaled by the splat) plus a color atlas texture indexed by per-splat UVs. Per-vertex
    /// color isn't read by stock materials, so color rides through the atlas instead.
    private static func buildSplatMesh(_ points: [SplatPoint]) async throws -> (MeshResource, TextureResource) {
        let n = points.count
        let side = max(1, Int(Double(n).squareRoot().rounded(.up)))
        let sizeFactor: Float = 2.0   // quad half-extent in splat sigmas

        var positions = [SIMD3<Float>](); positions.reserveCapacity(n * 4)
        var uvs = [SIMD2<Float>](); uvs.reserveCapacity(n * 4)
        var indices = [UInt32](); indices.reserveCapacity(n * 6)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        for (i, p) in points.enumerated() {
            let s = p.scale.asLinearFloat
            let ax = p.rotation.act(SIMD3<Float>(1, 0, 0)) * (s.x * sizeFactor)
            let ay = p.rotation.act(SIMD3<Float>(0, 1, 0)) * (s.y * sizeFactor)
            let c = p.position
            let base = UInt32(i * 4)
            positions.append(c - ax - ay)
            positions.append(c + ax - ay)
            positions.append(c + ax + ay)
            positions.append(c - ax + ay)

            let u = (Float(i % side) + 0.5) / Float(side)
            let v = (Float(i / side) + 0.5) / Float(side)
            for _ in 0..<4 { uvs.append(SIMD2(u, v)) }

            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])

            let col = p.color.asSRGBUInt8
            let pix = i * 4   // pixel (i%side, i/side) row-major == i
            pixels[pix + 0] = col.x; pixels[pix + 1] = col.y
            pixels[pix + 2] = col.z; pixels[pix + 3] = 255
        }

        var desc = MeshDescriptor(name: "splatQuads")
        desc.positions = MeshBuffer(positions)
        desc.textureCoordinates = MeshBuffer(uvs)
        desc.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [desc])

        let texture = try await colorAtlas(pixels, side: side)
        return (mesh, texture)
    }

    /// Wraps a tightly-packed RGBA buffer into a non-interpolated color atlas texture.
    private static func colorAtlas(_ rgba: [UInt8], side: Int) async throws -> TextureResource {
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: side, height: side,
                               bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent)
        else { throw SplatRKError.atlasFailed }
        return try await TextureResource(image: cg, withName: "splatColorAtlas",
                                         options: .init(semantic: .color))
    }

    // MARK: - Framing (centroid recentre + upright flip), mirrors SplatVisionRenderer

    private static func downsample(_ points: [SplatPoint], to budget: Int) -> [SplatPoint] {
        guard points.count > budget else { return points }
        let stride = Int((Double(points.count) / Double(budget)).rounded(.up))
        var out = [SplatPoint](); out.reserveCapacity(points.count / stride + 1)
        var i = 0
        while i < points.count { out.append(points[i]); i += stride }
        return out
    }

    private static func framing(_ points: [SplatPoint],
                                flipUpsideDown: Bool) -> (simd_float4x4, SplatLocomotion) {
        var sum = SIMD3<Float>.zero
        for p in points { sum += p.position }
        let center = sum / Float(points.count)
        var distSum: Float = 0
        for p in points { distSum += simd_length(p.position - center) }
        let meanRadius = max(distSum / Float(points.count), 0.001)

        var calibration = matrix_identity_float4x4
        calibration.columns.3 = SIMD4(-center.x, -center.y, -center.z, 1)
        if flipUpsideDown {
            var flip = matrix_identity_float4x4
            flip.columns.1.y = -1; flip.columns.2.z = -1   // 180° about X
            calibration = flip * calibration
        }
        let loco = SplatLocomotion(position: SIMD3(0, 0, meanRadius * 3), span: max(meanRadius, 1))
        return (calibration, loco)
    }
}

private enum SplatRKError: Error { case atlasFailed }

/// The control pill that rides on the head anchor: 結束 (top) · AI orb (centre) · 上一頁
/// (bottom). Self-contained, high-contrast styling so it stays legible against the dark
/// immersive scene (the glass `.ultraThinMaterial` bar washes out to near-invisible on
/// black, which is why this spike uses an explicit solid pill instead).
private struct SplatRKHUD: View {
    var onPrev: () -> Void
    var onExit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            pillButton("xmark", label: "結束", tint: .red, action: onExit)

            // AI 對話 orb (decorative for this spike; real VoiceMascot lands in Step 2).
            Circle()
                .fill(RadialGradient(colors: [Color.orange, Color.orange.opacity(0.25)],
                                     center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 42))
                .frame(width: 66, height: 66)
                .overlay(Text("AI").font(.caption.weight(.bold)).foregroundStyle(.white))
                .shadow(color: .orange.opacity(0.6), radius: 10)

            pillButton("chevron.left", label: "上一頁", tint: .white, action: onPrev)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(width: 150)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous)
            .strokeBorder(.white.opacity(0.4), lineWidth: 1))
    }

    private func pillButton(_ system: String, label: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system).font(.system(size: 22, weight: .semibold))
                Text(label).font(.caption2)
            }
            .foregroundStyle(tint)
            .frame(width: 92, height: 56)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Dev-menu launcher: opens / closes the `splat-rk` immersive space.
struct SplatRKLauncherView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isOpen = false

    var body: some View {
        ZStack {
            // Drop the opaque cream background once immersed so the floating launcher
            // doesn't clutter the world — leave only a small "Leave" affordance.
            if !isOpen { WarmBackground() }

            VStack(spacing: 20) {
                if isOpen {
                    Text("RK world open — turn your head; the right-side pill should follow.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button("Leave RK World") { leave() }
                        .buttonStyle(.bordered)
                } else {
                    Text("Splat RK — HUD spike")
                        .font(.title2.weight(.semibold))
                    Text("Opens a RealityView immersive space with a head-anchored control pill pinned to the right. Move your head — the pill should follow.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("Enter RK World") {
                        Task {
                            if case .opened = await openImmersiveSpace(id: "splat-rk") { isOpen = true }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
        }
    }

    private func leave() {
        Task { await dismissImmersiveSpace(); isOpen = false }
    }
}

/// Head-anchored hold-to-move pad: press-and-hold a direction to walk; release to stop.
/// Writes to `SplatManualInput` (the no-controller locomotion fallback) so the world is
/// walkable in the Simulator without a gamepad.
private struct RKMovePad: View {
    var body: some View {
        VStack(spacing: 8) {
            moveBtn("arrow.up", forward: 1)
            HStack(spacing: 8) {
                moveBtn("arrow.turn.up.left", turn: -1)
                moveBtn("arrow.down", forward: -1)
                moveBtn("arrow.turn.up.right", turn: 1)
            }
        }
        .padding(16)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }

    private func moveBtn(_ system: String, forward: Float = 0, turn: Float = 0) -> some View {
        Image(systemName: system)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 48)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // minimumDistance 0 → fires on touch-down (hold) and clears on release.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in SplatManualInput.shared.set(forward: forward, turn: turn) }
                .onEnded { _ in SplatManualInput.shared.set(forward: 0, turn: 0) })
    }
}

/// Drives `SplatLocomotion` each frame from the move pad (and a gamepad if present),
/// moving the world `root` by the inverse player transform — the same pattern as
/// `ParametricLocomotor` in `ImmersiveWorldView`, but with the on-screen manual fallback
/// wired in so it walks in the Simulator.
@MainActor
final class RKSpikeLocomotor {
    private var loco = SplatLocomotion()
    private weak var root: Entity?
    private var subscription: EventSubscription?

    func start(loco: SplatLocomotion, root: Entity, content: RealityViewContent) {
        self.root = root
        self.loco = loco
        SplatManualInput.shared.reset()
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self, let root = self.root else { return }
            self.loco.tick(deltaTime: Float(event.deltaTime),
                           gamepad: rkGamepad(),
                           manual: SplatManualInput.shared.snapshot())
            root.transform = Transform(matrix: self.loco.playerTransform().inverse)
        }
    }
}

/// First connected controller's extended gamepad, or nil (Simulator has none).
private func rkGamepad() -> GCExtendedGamepad? {
    GCController.controllers().lazy.compactMap { $0.extendedGamepad }.first
}

#endif

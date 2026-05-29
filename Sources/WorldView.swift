import SwiftUI
#if !os(visionOS)
import RealityKit
import UIKit
import GameController
#endif

/// Shows the resolved world.
/// - iOS/iPadOS: full-screen 360-degree view.
/// - visionOS: panel controls that open the immersive space.
struct WorldView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        #if os(visionOS)
        VisionWorldPanel()
        #else
        iOSWorldView()
        #endif
    }
}

#if os(visionOS)
import SwiftUI

/// visionOS panel for opening and closing the immersive space.
struct VisionWorldPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 22) {
            Text("Your world is ready")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(appState.world?.title ?? "Your world")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            if let blurb = appState.world?.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(isOpen ? "Leave the world" : "Step into your world") {
                Task {
                    if isOpen {
                        await dismissImmersiveSpace()
                        isOpen = false
                    } else {
                        if case .opened = await openImmersiveSpace(id: "world") {
                            isOpen = true
                        }
                    }
                }
            }
            .buttonStyle(PrimaryPillButtonStyle())

            Button("Start over") { appState.restart() }
                .buttonStyle(SecondaryPillButtonStyle())
        }
        .frame(maxWidth: 520)
        .padding(44)
    }
}
#else

/// iOS/iPadOS full-screen 360-degree view with a readable result overlay.
struct iOSWorldView: View {
    @Environment(AppState.self) private var appState
    @State private var showOverlay = false
    @State private var showHint = true
    @State private var walkable = false
    @State private var narrator = NarrationService()

    /// Composes and speaks the guide's entry narration from the user's scores.
    private func speakEntryNarration() {
        guard let world = appState.world,
              let scores = appState.axisScores,
              let params = appState.worldParams else { return }
        let text = NarrationComposer.entryNarration(world: world, scores: scores, params: params)
        narrator.speak(text)
    }

    /// Tapping the mascot replays the welcome — or stops it if already speaking.
    private func toggleNarration() {
        if narrator.isSpeaking { narrator.stop() } else { speakEntryNarration() }
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                if walkable, let splatURL = appState.generatedSplatURL {
                    SplatWorldView(remoteURL: splatURL)
                        .ignoresSafeArea()
                } else if let wp = appState.worldParams {
                    ParametricWorldView(params: wp)
                        .ignoresSafeArea()
                } else if let world = appState.world {
                    Immersive360View(world: world, overrideImage: appState.generatedPano)
                        .ignoresSafeArea()
                }

                // Gradient + text overlay — hidden until tapped
                Group {
                    LinearGradient(
                        colors: [.clear, .black.opacity(isLandscape ? 0.74 : 0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    VStack(spacing: isLandscape ? 10 : 14) {
                        Spacer(minLength: 0)

                        VStack(spacing: 8) {
                            Text(appState.world?.title ?? "")
                                .font((isLandscape ? Font.title3 : Font.title2).weight(.semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 8)
                                .multilineTextAlignment(.center)

                            if let blurb = appState.world?.blurb, !blurb.isEmpty {
                                Text(blurb)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.88))
                                    .shadow(radius: 8)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(isLandscape ? 2 : 3)
                            }
                        }
                        .frame(maxWidth: isLandscape ? 680 : 560)

                        if appState.generatedSplatURL != nil {
                            Button(walkable ? "Panorama view" : "Walk inside (3D)") {
                                walkable.toggle()
                            }
                            .buttonStyle(SecondaryPillButtonStyle())
                        }

                        Button("Start over") { appState.restart() }
                            .buttonStyle(PrimaryPillButtonStyle())
                    }
                    .padding(.horizontal, isLandscape ? 32 : 24)
                    .padding(.bottom, isLandscape ? 28 : 44)
                }
                .opacity(showOverlay ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: showOverlay)

                // Entry hint — fades out after 2 s or on first tap
                VStack {
                    Spacer()
                    Text("Tap to reveal")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, isLandscape ? 20 : 32)
                }
                .opacity(showHint && !showOverlay ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: showHint)
                .animation(.easeOut(duration: 0.25), value: showOverlay)
                .allowsHitTesting(false)

                // Voice-companion mascot — speaks the welcome on entry; tap to replay.
                VStack {
                    HStack {
                        Spacer()
                        OrbView(size: 76, isSpeaking: narrator.isSpeaking)
                            .contentShape(Circle())
                            .onTapGesture { toggleNarration() }
                            .accessibilityLabel("Replay your world's welcome")
                            .padding(.trailing, isLandscape ? 28 : 20)
                            .padding(.top, isLandscape ? 16 : 24)
                    }
                    Spacer()
                }
            }
            .onTapGesture {
                showHint = false
                showOverlay.toggle()
            }
            .task {
                try? await Task.sleep(for: .seconds(2))
                showHint = false
            }
            .task {
                // A short beat so the world has rendered before the guide speaks.
                try? await Task.sleep(for: .milliseconds(900))
                speakEntryNarration()
            }
            .onDisappear { narrator.stop() }
        }
    }
}

// MARK: - ParametricWorldView helpers

/// 3-keyframe linear interpolation of Kelvin → UIColor.
/// 3500 K = amber warm, 5500 K = neutral white, 7000 K = cool blue-white.
private func colorFromKelvin(_ kelvin: Float) -> UIColor {
    if kelvin <= 5500 {
        let t = CGFloat((kelvin - 3500) / (5500 - 3500))
        return UIColor(red: 1.0, green: 0.76 + 0.24 * t, blue: 0.44 + 0.56 * t, alpha: 1)
    } else {
        let t = CGFloat((kelvin - 5500) / (7000 - 5500))
        return UIColor(red: 1.0 - 0.15 * t, green: 1.0 - 0.07 * t, blue: 1.0, alpha: 1)
    }
}

/// Returns evenly-spaced glow-orb ModelEntities on the scene's floor perimeter.
/// `count == 0` returns empty (no companions). Used for 軸1 social density.
private func companionOrbs(count: Int, bounds: BoundingBox, span: Float) -> [ModelEntity] {
    guard count > 0 else { return [] }
    let perimeter = max(bounds.extents.x, bounds.extents.z) * 0.45
    let floorY = bounds.min.y + span * 0.05
    let orbRadius = span * 0.02
    return (0..<count).map { i in
        let angle = Float(i) * (.pi * 2 / Float(count))
        let mesh = MeshResource.generateSphere(radius: orbRadius)
        let mat = UnlitMaterial(color: UIColor(white: 0.9, alpha: 0.8))
        let orb = ModelEntity(mesh: mesh, materials: [mat])
        orb.position = SIMD3<Float>(bounds.center.x + cos(angle) * perimeter,
                                     floorY,
                                     bounds.center.z + sin(angle) * perimeter)
        return orb
    }
}

// MARK: - ParametricWorldView

/// Production walk-in world driven by `WorldParams`.
/// Loads the USDZ for `params.archetype`, then tunes:
///   - 軸4: DirectionalLight intensity + color temperature + saturation overlay
///   - 軸1: ambient companion orbs (social density)
/// Drag to look, pinch to move, ○ to reset (PS5/DualSense). Reuses `WorldCameraRig`.
struct ParametricWorldView: View {
    let params: WorldParams

    @State private var rig = WorldCameraRig()
    @State private var gamepad = GamepadManager()
    @State private var status: PVStatus = .loading
    @State private var lastDrag: CGSize = .zero
    @State private var lastMag: CGFloat = 1
    // Debug state — always compiled; overlay only shown in DEBUG builds.
    @State private var debugCalmVivid: Double = 0.5
    @State private var debugBelonging: Double = 0.5
    @State private var debugVersion: Int = 0

    private enum PVStatus { case loading, ready, failed }

    private var effectiveParams: WorldParams {
        #if DEBUG
        let s = AxisScores(
            autonomyBelonging: debugBelonging,
            exploreStable: 0.5,
            expressionConnection: 0.5,
            calmVivid: debugCalmVivid,
            hope: .ownPath
        )
        return WorldMapper.map(s)
        #else
        return params
        #endif
    }

    var body: some View {
        // Capture effective params once per body evaluation so the make closure
        // and the saturation overlay both read the same snapshot.
        let ep = effectiveParams
        ZStack {
            Color.black.ignoresSafeArea()

            RealityView { content in
                guard let model = try? await Entity(named: params.archetype.usdzName) else {
                    status = .failed; return
                }
                content.add(model)

                let bounds = model.visualBounds(relativeTo: nil)
                let span = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                let eye = SIMD3<Float>(bounds.center.x,
                                      bounds.center.y + bounds.extents.y * 0.15,
                                      bounds.center.z)

                // 軸4: three directional lights with intensity + color temperature.
                let warmth = colorFromKelvin(ep.colorTemperature)
                for (dir, mult): (SIMD3<Float>, Float) in [
                    ([1, 1, 1], 1.0), ([-1, 0.6, -0.6], 0.55), ([0, 0.4, 1], 0.35)
                ] {
                    let light = DirectionalLight()
                    light.light.intensity = ep.lightIntensity * mult
                    light.light.color = warmth
                    light.look(at: .zero, from: dir, relativeTo: nil)
                    content.add(light)
                }

                // 軸1: companion orbs placed on the floor perimeter.
                for orb in companionOrbs(count: ep.socialDensity, bounds: bounds, span: span) {
                    content.add(orb)
                }

                // Camera + WorldCameraRig (same pattern as USDZTestView).
                let camera = PerspectiveCamera()
                var comp = camera.camera
                comp.near = max(0.01, span * 0.001)
                comp.far = span * 50 + 100
                camera.camera = comp
                content.add(camera)
                rig.configure(camera: camera, position: eye, span: span)
                rig.apply()
                rig.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    rig.tick(deltaTime: Float(event.deltaTime), gamepad: gamepad.gamepad)
                    rig.apply()
                }
                status = .ready
            }
            // id changes trigger full RealityView rebuild (archetype switch or debug reload).
            .id("\(params.archetype)-\(debugVersion)")
            .gesture(DragGesture()
                .onChanged { v in
                    rig.look(deltaX: Float(v.translation.width - lastDrag.width),
                             deltaY: Float(v.translation.height - lastDrag.height))
                    lastDrag = v.translation
                }
                .onEnded { _ in lastDrag = .zero })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in
                    rig.dolly(delta: Float(v.magnification - lastMag))
                    lastMag = v.magnification
                }
                .onEnded { _ in lastMag = 1 })
            .ignoresSafeArea()

            // 軸4: saturation — SwiftUI grey overlay on top of RealityKit scene.
            // saturation 1.1 (vivid) → opacity ≈ 0 (full color)
            // saturation 0.5 (calm)  → opacity = 0.5 (noticeably desaturated)
            Color.gray
                .opacity(max(0, 1.0 - ep.saturation))
                .blendMode(.saturation)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if status == .failed {
                Label("World load failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.yellow)
            }

            #if DEBUG
            debugOverlay
            #endif
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                Text("DEBUG — Route D parametric world")
                    .font(.caption2.weight(.bold)).foregroundStyle(.yellow)
                Text("calm↔vivid \(debugCalmVivid, specifier: "%.2f")  ·  orbs \(effectiveParams.socialDensity)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.8))
                Slider(value: $debugCalmVivid).tint(.yellow)
                Text("auto↔belong \(debugBelonging, specifier: "%.2f")")
                    .font(.caption2).foregroundStyle(.white.opacity(0.8))
                Slider(value: $debugBelonging).tint(.orange)
                Button("↺  Reload world (companions)") { debugVersion += 1 }
                    .font(.caption2.weight(.semibold)).foregroundStyle(.yellow)
            }
            .padding(12)
            .background(.black.opacity(0.6))
            .cornerRadius(10)
            .padding(.bottom, 56)
            .padding(.horizontal, 16)
        }
    }
    #endif
}
#endif

import SwiftUI
import RealityKit
#if !os(visionOS)
import GameController
#endif

// ⚠️ DEV / VERIFICATION ONLY — do NOT ship.
// `launchIntoTest` reroutes the whole app straight into the USDZ viewer,
// bypassing the splash / quiz / world flow. Set back to `false` before any
// real demo or submit so the normal experience returns.
enum USDZDebug {
    static let launchIntoTest = false

    /// USDZ resources bundled with the app (file name without extension).
    static let models = [
        "Cozy_living_room_baked",
        "Free_Low_Poly_Forest",
        "FREE_Dirt_Road_Through_Forest",
    ]
}

#if !os(visionOS)

/// Holds the first-person camera state and applies it to the RealityKit camera
/// each frame. Both touch gestures and the PS5 / extended gamepad mutate this
/// same rig, so they coexist without fighting over SwiftUI state.
@MainActor
final class WorldCameraRig {
    var yaw: Float = 0
    var pitch: Float = 0
    var position: SIMD3<Float> = .zero
    /// Largest dimension of the loaded scene; movement/look speed scale by it.
    var span: Float = 1

    weak var camera: PerspectiveCamera?
    var updateSubscription: EventSubscription?

    private var initialPosition: SIMD3<Float> = .zero
    private var initialYaw: Float = 0
    private var initialPitch: Float = 0
    private var resetWasPressed = false

    private let lookSpeed: Float = 2.4          // rad/sec at full stick deflection
    private let moveFraction: Float = 0.6       // scene spans/sec at full deflection
    private let deadzone: Float = 0.1

    /// Yaw-only basis so left-stick / pinch movement stays on the horizontal
    /// plane (vertical is reserved for the triggers).
    private var moveForward: SIMD3<Float> {
        simd_quatf(angle: yaw, axis: [0, 1, 0]).act([0, 0, -1])
    }
    private var moveRight: SIMD3<Float> {
        simd_quatf(angle: yaw, axis: [0, 1, 0]).act([1, 0, 0])
    }

    func configure(camera: PerspectiveCamera, position: SIMD3<Float>, span: Float) {
        self.camera = camera
        self.position = position
        self.span = span
        self.yaw = 0
        self.pitch = 0
        initialPosition = position
        initialYaw = 0
        initialPitch = 0
    }

    /// Camera-less setup for renderers that consume a view matrix directly (e.g. the
    /// MetalSplatter splat path) instead of a RealityKit `PerspectiveCamera`.
    func configure(position: SIMD3<Float>, span: Float) {
        self.camera = nil
        self.position = position
        self.span = span
        self.yaw = 0
        self.pitch = 0
        initialPosition = position
        initialYaw = 0
        initialPitch = 0
    }

    func apply() {
        camera?.position = position
        camera?.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// World→view matrix for the splat renderer: the inverse of the camera's world
    /// transform `T(position) · R(yaw,pitch)`. Same orientation convention as `apply()`.
    func viewMatrix() -> simd_float4x4 {
        let r = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        var world = matrix_float4x4(r)
        world.columns.3 = SIMD4(position, 1)
        return simd_inverse(world)
    }

    /// Integrates one frame of gamepad input. No-op (apply still runs) when no
    /// controller is connected, leaving touch gestures in control.
    func tick(deltaTime dt: Float, gamepad gp: GCExtendedGamepad?) {
        guard let gp else { return }

        // Right stick → look.
        yaw -= dead(gp.rightThumbstick.xAxis.value) * lookSpeed * dt
        pitch = clampPitch(pitch + dead(gp.rightThumbstick.yAxis.value) * lookSpeed * dt)

        // Left stick → move on the horizontal plane.
        let speed = span * moveFraction * dt
        position += moveForward * (dead(gp.leftThumbstick.yAxis.value) * speed)
        position += moveRight * (dead(gp.leftThumbstick.xAxis.value) * speed)

        // Triggers → vertical (R2 up, L2 down, analog).
        position.y += (gp.rightTrigger.value - gp.leftTrigger.value) * speed

        // ○ (buttonB) → reset, edge-triggered.
        let pressed = gp.buttonB.isPressed
        if pressed && !resetWasPressed { resetToInitial() }
        resetWasPressed = pressed
    }

    func resetToInitial() {
        position = initialPosition
        yaw = initialYaw
        pitch = initialPitch
    }

    // Gesture deltas feed straight into the rig.
    func look(deltaX: Float, deltaY: Float) {
        yaw -= deltaX * 0.005
        pitch = clampPitch(pitch + deltaY * 0.005)
    }
    func dolly(delta: Float) {
        position += moveForward * (delta * span * 0.5)
    }

    private func dead(_ v: Float) -> Float { abs(v) < deadzone ? 0 : v }
    private func clampPitch(_ p: Float) -> Float { min(max(p, -.pi * 0.49), .pi * 0.49) }
}

/// iOS / iPadOS first-person USDZ world inspector. The camera sits *inside* the
/// scene. Touch: drag to look, pinch to move. PS5 / extended gamepad: left stick
/// move, right stick look, R2/L2 up/down, ○ reset.
struct USDZTestView: View {
    @State private var modelIndex = 0
    @State private var rig = WorldCameraRig()
    @State private var gamepad = GamepadManager()
    @State private var status: Status = .loading

    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    private enum Status: Equatable { case loading, ready, failed }

    private var modelName: String { USDZDebug.models[modelIndex] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RealityView { content in
                guard let model = try? await Entity(named: modelName) else {
                    status = .failed
                    return
                }
                content.add(model)

                let bounds = model.visualBounds(relativeTo: nil)
                let span = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                let eye = SIMD3(bounds.center.x,
                                bounds.center.y + bounds.extents.y * 0.15,
                                bounds.center.z)

                for dir in [SIMD3<Float>(1, 1, 1), SIMD3<Float>(-1, 0.6, -0.6), SIMD3<Float>(0, 0.4, 1)] {
                    let light = DirectionalLight()
                    light.light.intensity = 1500
                    light.look(at: .zero, from: dir, relativeTo: nil)
                    content.add(light)
                }

                let camera = PerspectiveCamera()
                var component = camera.camera
                component.near = max(0.01, span * 0.001)
                component.far = span * 50 + 100
                camera.camera = component
                content.add(camera)

                rig.configure(camera: camera, position: eye, span: span)
                rig.apply()
                rig.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    rig.tick(deltaTime: Float(event.deltaTime), gamepad: gamepad.gamepad)
                    rig.apply()
                }

                status = .ready
            }
            .id(modelName)
            .gesture(lookGesture)
            .simultaneousGesture(dollyGesture)
            .ignoresSafeArea()

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
            HStack(spacing: 12) {
                Picker("Model", selection: $modelIndex) {
                    ForEach(USDZDebug.models.indices, id: \.self) { i in
                        Text(USDZDebug.models[i]).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                if gamepad.isConnected {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }

                Spacer()

                if status == .loading { ProgressView().tint(.white) }
                if status == .failed {
                    Label("Load failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            Text(gamepad.isConnected
                 ? "Left stick move · right stick look · R2/L2 up/down · ○ reset"
                 : "Drag to look around · pinch to move")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 20)
        }
    }
}

#else

/// visionOS USDZ inspector: a windowed preview (model floats in the volume, drag to
/// rotate) plus a "Walk inside" button that opens the first-person immersive walk-in
/// (`ImmersiveUSDZView`), matching the iPad first-person viewer.
struct USDZTestView: View {
    @State private var modelIndex = 0
    @State private var yaw: Float = 0
    @State private var liveYaw: Float = 0
    @State private var status: String = "Loading…"
    @State private var gamepad = GamepadManager()

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(ImmersiveSpaceController.self) private var spaces

    private var modelName: String { USDZDebug.models[modelIndex] }

    var body: some View {
        VStack(spacing: 18) {
            Picker("Model", selection: $modelIndex) {
                ForEach(USDZDebug.models.indices, id: \.self) { i in
                    Text(USDZDebug.models[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)

            RealityView { content in
                guard let model = try? await Entity(named: modelName) else {
                    status = "Load failed"
                    return
                }
                let bounds = model.visualBounds(relativeTo: nil)
                let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                let scale = maxExtent > 0 ? 0.4 / maxExtent : 1
                model.scale = SIMD3(repeating: scale)
                model.position = -bounds.center * scale

                let pivot = Entity()
                pivot.name = "pivot"
                pivot.addChild(model)
                content.add(pivot)
                status = ""
            } update: { content in
                content.entities.first { $0.name == "pivot" }?
                    .orientation = simd_quatf(angle: yaw + liveYaw, axis: [0, 1, 0])
            }
            .id(modelName)
            .frame(minWidth: 400, minHeight: 400)
            .gesture(
                DragGesture()
                    .onChanged { liveYaw = Float($0.translation.width) * 0.01 }
                    .onEnded { _ in yaw += liveYaw; liveYaw = 0 }
            )

            if !status.isEmpty {
                Text(status).foregroundStyle(.secondary)
            }

            // First-person walk-in (full-immersion space). Drag the preview above to
            // pre-orient; walk with a controller once inside (head tracking looks around).
            Button("Walk inside") {
                Task {
                    await spaces.present(id: "usdz",
                                         dismiss: { await dismissImmersiveSpace() },
                                         open: { await openImmersiveSpace(id: "usdz", value: modelName) })
                }
            }
            .buttonStyle(.borderedProminent)

            Label(gamepad.isConnected
                  ? "Controller connected · left stick move · right stick turn · R2/L2 up/down · ○ reset"
                  : "Connect a controller to walk inside · head tracking looks around",
                  systemImage: gamepad.isConnected ? "gamecontroller.fill" : "gamecontroller")
                .font(.footnote)
                .foregroundStyle(gamepad.isConnected ? .green : .secondary)
        }
        .padding(28)
    }
}

#endif

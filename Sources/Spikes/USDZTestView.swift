import SwiftUI
import RealityKit
import UniformTypeIdentifiers
#if !os(visionOS)
import GameController
#endif

// ⚠️ DEV / VERIFICATION ONLY — do NOT ship.
// `launchIntoTest` reroutes the whole app straight into the USDZ viewer,
// bypassing the splash / quiz / world flow. Set back to `false` before any
// real demo or submit so the normal experience returns.
enum USDZDebug {
    static let launchIntoTest = false
}

// MARK: - Import from Files + recents (USDZ is no longer bundled; load from the Files app)

/// Copies a user-picked `.usdz` (from the Files app, via `fileImporter`) into a durable
/// app folder so it survives restarts and outlives the picker's security scope.
/// Mirrors `SplatImporter`. Platform-agnostic (Foundation only).
enum USDZImporter {
    /// Durable home for imported models, under Documents (caches can be evicted).
    static func importedDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ImportedUSDZ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies a security-scoped picked file into `importedDir`, overwriting any file of
    /// the same name, and returns the stored filename. Scope is held only for the copy.
    static func storeImported(_ picked: URL) throws -> String {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        let filename = picked.lastPathComponent
        let dest = importedDir().appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: picked, to: dest)
        return filename
    }
}

/// A `.usdz` imported from the Files app, remembered so the viewer can reopen it.
struct SavedUSDZModel: Codable, Identifiable {
    let id: String          // the stored filename (re-importing the same name updates it)
    let name: String        // display name (filename without extension)
    let createdAt: Date
    let filename: String     // under `USDZImporter.importedDir()`

    /// Rebuilds the local URL from Documents each time (sandbox path can change between launches).
    func resolvedURL() -> URL { USDZImporter.importedDir().appendingPathComponent(filename) }
}

/// UserDefaults-backed list of imported models (dev-only convenience). Mirrors `SplatLibrary`.
enum USDZLibrary {
    private static let key = "usdz.library.v1"

    static func load() -> [SavedUSDZModel] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let models = try? JSONDecoder().decode([SavedUSDZModel].self, from: data)
        else { return [] }
        return models
    }

    /// Insert at the front, de-duplicating by id (newest wins).
    static func add(_ model: SavedUSDZModel) {
        var models = load().filter { $0.id != model.id }
        models.insert(model, at: 0)
        save(models)
    }

    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    private static func save(_ models: [SavedUSDZModel]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
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
    @State private var saved: [SavedUSDZModel] = USDZLibrary.load()
    @State private var selectedID: String?
    @State private var showImporter = false
    @State private var rig = WorldCameraRig()
    @State private var gamepad = GamepadManager()
    @State private var status: Status = .loading

    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    private enum Status: Equatable { case loading, ready, failed }

    private var selected: SavedUSDZModel? { saved.first { $0.id == selectedID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RealityView { content in
                guard let url = selected?.resolvedURL(),
                      let model = try? await Entity(contentsOf: url) else {
                    status = .failed
                    return
                }
                status = .loading
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
            .id(selected?.id ?? "none")
            .gesture(lookGesture)
            .simultaneousGesture(dollyGesture)
            .ignoresSafeArea()

            if saved.isEmpty {
                Text("Import a .usdz from Files to begin")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            overlay
        }
        .onAppear { if selectedID == nil { selectedID = saved.first?.id } }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.usdz],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let picked = urls.first else { return }
        guard let filename = try? USDZImporter.storeImported(picked) else {
            status = .failed
            return
        }
        let model = SavedUSDZModel(id: filename,
                                   name: picked.deletingPathExtension().lastPathComponent,
                                   createdAt: Date(),
                                   filename: filename)
        USDZLibrary.add(model)
        saved = USDZLibrary.load()
        selectedID = model.id
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
                Picker("Model", selection: $selectedID) {
                    ForEach(saved) { model in
                        Text(model.name).tag(Optional(model.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .disabled(saved.isEmpty)

                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
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
    @State private var saved: [SavedUSDZModel] = USDZLibrary.load()
    @State private var selectedID: String?
    @State private var showImporter = false
    @State private var yaw: Float = 0
    @State private var liveYaw: Float = 0
    @State private var status: String = ""
    @State private var gamepad = GamepadManager()

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private var selected: SavedUSDZModel? { saved.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Picker("Model", selection: $selectedID) {
                    ForEach(saved) { model in
                        Text(model.name).tag(Optional(model.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(saved.isEmpty)

                Button("Load from Files…") { showImporter = true }
            }

            RealityView { content in
                guard let url = selected?.resolvedURL(),
                      let model = try? await Entity(contentsOf: url) else {
                    status = saved.isEmpty ? "Import a .usdz from Files" : "Load failed"
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
            .id(selected?.id ?? "none")
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
                guard let url = selected?.resolvedURL() else { return }
                Task { await openImmersiveSpace(id: "usdz", value: url) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected == nil)

            Label(gamepad.isConnected
                  ? "Controller connected · left stick move · right stick turn · R2/L2 up/down · ○ reset"
                  : "Connect a controller to walk inside · head tracking looks around",
                  systemImage: gamepad.isConnected ? "gamecontroller.fill" : "gamecontroller")
                .font(.footnote)
                .foregroundStyle(gamepad.isConnected ? .green : .secondary)
        }
        .padding(28)
        .onAppear { if selectedID == nil { selectedID = saved.first?.id } }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.usdz],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let picked = urls.first else { return }
        guard let filename = try? USDZImporter.storeImported(picked) else {
            status = "Import failed"
            return
        }
        let model = SavedUSDZModel(id: filename,
                                   name: picked.deletingPathExtension().lastPathComponent,
                                   createdAt: Date(),
                                   filename: filename)
        USDZLibrary.add(model)
        saved = USDZLibrary.load()
        selectedID = model.id
    }
}

#endif

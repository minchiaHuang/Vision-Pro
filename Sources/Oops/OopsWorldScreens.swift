import SwiftUI

// MARK: - OopsAnswers → MuseumAnswers adapter

extension MuseumAnswers {
    /// Builds the Curator's typed inputs from the finished OopsFlow quiz answers.
    /// Mapping (see `OopsContent.questions`): q1 age-range pill → `age` (lower bound),
    /// q2 → `city`, q3 → `role` (the Call), q4 → `currentSelf`, q5 → `fear`, q6 → `sacrifice`.
    /// `worthIt` is left blank — OopsFlow doesn't ask it, so the Curator infers it.
    init(oops: OopsAnswers) {
        func text(_ id: String) -> String {
            (oops.quizText[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.init()
        role        = text("q3")
        city        = text("q2")
        currentSelf = text("q4")
        fear        = text("q5")
        sacrifice   = text("q6")
        // q1 is a 4-way age-range pill; map its index to the lower bound of the range.
        age = [0: 17, 1: 20, 2: 25, 3: 30][oops.quiz["q1"] ?? -1] ?? 22
    }
}

// MARK: - Generating interstitial

/// Spinner + "Building your world…" while the Hero's-Journey image series is generated, then
/// advances to the preview. Generated images are stored on `AppState` for the gallery to show.
struct GeneratingScreen: View {
    @Environment(AppState.self) private var appState
    /// The user's "ideal self" goal that drives the generated series.
    let goal: String
    let onDone: () -> Void

    @State private var statusText = "Reading your answer…"

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)
            VStack(spacing: 38) {
                OopsSpinner()
                Text("Building your world…")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(statusText)
                    .oopsSub(20)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                    .id(statusText)                  // re-identity each stage so it crossfades
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.5), value: statusText)
        }
        .task { await runGeneration() }
    }

    /// Generates the 5-image journey from `goal`, stores it on `AppState`, then advances. On
    /// failure (or missing key) the result is empty and the gallery falls back to its bundled
    /// placeholders — the flow always completes so the user is never trapped.
    private func runGeneration() async {
        let images = await OpenAIImageService.generateJourney(goal: goal) { done, total in
            statusText = done >= total
                ? "Adding the finishing touches…"
                : "Painting scene \(done + 1) of \(total)…"
        }
        appState.galleryImages = images
        onDone()
    }
}

// MARK: - Previews

#Preview("Generating") {
    GeneratingScreen(goal: "I want to be a world class ballerina", onDone: {})
        .environment(AppState())
        .preferredColorScheme(.dark)
}

// MARK: - 09 · World (hosts the existing 3D world)

/// iPad: "Enter Now" enters the Richards Art Gallery as a first-person USDZ world
/// (ParametricWorldView). A glass close control overlays the top-left to leave to the
/// reflection flow. (On visionOS the gallery opens as a fully-immersive RealityKit
/// ImmersiveSpace via `OopsFlowView.enterWorld` — this container is not used there.)
struct OopsWorldContainer: View {
    let onExit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorldView(onExit: onExit)
                .ignoresSafeArea()

            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .padding(.top, 28)
            .accessibilityLabel("Leave world")
        }
    }
}

#if os(visionOS)

// MARK: - 09 · World controls (visionOS floating panel)

/// Floating control panel shown while the Oops 6DoF splat world is open. Mirrors the dev
/// `SplatExitControls`, but its exit returns the user to the Oops *reflection* flow
/// (reopening the dev-menu window at `.reflection`) rather than the dev menu. It also
/// hosts on-screen hold-to-move controls so the world is walkable without a game
/// controller (e.g. in the Simulator).
struct OopsWorldControls: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var session = SplatSession.shared
    /// Guards `performExit` so the button tap and the gamepad ☰ request can't double-fire.
    @State private var isExiting = false

    var body: some View {
        VStack(spacing: 18) {
            switch session.phase {
            case .ready:
                SplatMovePad()
                SplatManipulatePad() // TEMP: simulator gesture backdoor — remove after device test
                exitButton
                Text("Use the arrows below to move · tap Leave world to exit (or gamepad ☰)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                exitButton
            case .downloading, .preparing:
                loadingBody
            case .idle:
                // No world is loading — this panel shouldn't exist. Dismissed by `.task`.
                Color.clear
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .onChange(of: session.exitRequested) { _, requested in
            if requested { performExit() }
        }
        .onDisappear { SplatManualInput.shared.reset() }
        // A panel that finds the session idle has no world to show (e.g. a scene visionOS
        // tried to restore). Confirm it stays idle through the open race, then dismiss.
        .task(id: session.phase) {
            guard session.phase == .idle else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if session.phase == .idle { dismissWindow(id: "oops-world-controls") }
        }
    }

    private var loadingBody: some View {
        VStack(spacing: 12) {
            ProgressView(value: session.displayProgress)
                .progressViewStyle(.linear)
            Text(loadingLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingLabel: String {
        let pct = Int((session.displayProgress * 100).rounded())
        switch session.phase {
        case .downloading: return "Downloading… \(pct)%"
        default:           return "Preparing world… \(pct)%"
        }
    }

    private var exitButton: some View {
        Button { performExit() } label: {
            Label("Leave world", systemImage: "chevron.left")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isExiting)
    }

    /// Close the splat space, reset shared state, then reopen the dev-menu window at the
    /// Oops reflection screen. Shared by the button tap and the gamepad ☰ request.
    private func performExit() {
        guard !isExiting else { return }
        isExiting = true
        Task {
            await dismissImmersiveSpace()
            SplatManualInput.shared.reset()
            SplatModelManipulation.shared.reset()
            session.reset()
            // Drive the reopened dev-menu window straight to the Oops reflection screen.
            appState.oopsResumeScreen = .reflection
            appState.devActiveFeature = .oops
            openWindow(id: "dev-menu")
            dismissWindow(id: "oops-world-controls")
            dismissWindow(id: "oops-voice-orb")
        }
    }
}

// MARK: - Gallery controls (visionOS floating panel)

/// Floating control panel shown while the Richards Art Gallery ImmersiveSpace is open.
/// Unlike `OopsWorldControls` (which tracks `SplatSession` loading phases), the gallery
/// world is a standard RealityKit `Entity` load — no splat pipeline, no progress phases.
/// This panel therefore shows only the movement pad and an exit button immediately.
struct OopsGalleryControls: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isExiting = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Richards Art Gallery")
                .font(.headline)
            Text("Walk to explore · Use gamepad or arrows to move")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SplatMovePad()
            Button("Leave gallery", action: performExit)
                .buttonStyle(.borderedProminent)
                .disabled(isExiting)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func performExit() {
        guard !isExiting else { return }
        isExiting = true
        Task {
            await dismissImmersiveSpace()
            appState.worldParams = nil
            // Return to the Oops reflection screen (same pattern as OopsWorldControls).
            appState.oopsResumeScreen = .reflection
            appState.devActiveFeature = .oops
            openWindow(id: "dev-menu")
            dismissWindow(id: "oops-gallery-controls")
        }
    }
}

/// On-screen hold-to-move pad driving `SplatManualInput`, the no-controller locomotion
/// fallback. Press-and-hold a control to move; release to stop.
private struct SplatMovePad: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Hold to move").font(.caption).foregroundStyle(.secondary)
            moveButton("arrow.up", forward: 1)
            HStack(spacing: 10) {
                moveButton("arrow.turn.up.left", turn: -1)
                moveButton("arrow.down", forward: -1)
                moveButton("arrow.turn.up.right", turn: 1)
            }
        }
    }

    private func moveButton(_ system: String, forward: Float = 0, turn: Float = 0) -> some View {
        Image(systemName: system)
            .font(.title2.weight(.semibold))
            .frame(width: 64, height: 54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            // minimumDistance 0 → fires on touch-down (hold) and clears on release.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in SplatManualInput.shared.set(forward: forward, turn: turn) }
                .onEnded { _ in SplatManualInput.shared.set(forward: 0, turn: 0) })
    }
}

// TEMP: simulator gesture backdoor. The visionOS Simulator has no hands, so these
// on-screen hold buttons feed the SAME `SplatModelManipulation` sink as the device's
// two-hand pinch gesture — letting us verify the model rotate/scale maths in the sim.
// Remove this pad (and its two call sites) once validated on a real device.
struct SplatManipulatePad: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Rotate / scale model (sim)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                HoldRepeatButton(system: "arrow.counterclockwise") {
                    SplatModelManipulation.shared.add(yaw: -0.02, scaleMul: 1)
                }
                HoldRepeatButton(system: "arrow.clockwise") {
                    SplatModelManipulation.shared.add(yaw: 0.02, scaleMul: 1)
                }
                HoldRepeatButton(system: "plus.magnifyingglass") {
                    SplatModelManipulation.shared.add(yaw: 0, scaleMul: 1.01)
                }
                HoldRepeatButton(system: "minus.magnifyingglass") {
                    SplatModelManipulation.shared.add(yaw: 0, scaleMul: 0.99)
                }
            }
        }
    }
}

/// A button that repeatedly fires `action` (~60 Hz) while held — so the gesture maths gets
/// a continuous stream of deltas, not a single touch-down event. (Part of the TEMP backdoor.)
private struct HoldRepeatButton: View {
    let system: String
    let action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: system)
            .font(.title2.weight(.semibold))
            .frame(width: 64, height: 54)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in start() }
                .onEnded { _ in stop() })
    }

    private func start() {
        guard timer == nil else { return }
        action()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in action() }
    }
    private func stop() { timer?.invalidate(); timer = nil }
}

#endif

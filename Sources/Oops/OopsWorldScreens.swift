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
    /// The finished OopsFlow answers that drive the Curator pipeline (mapped to `MuseumAnswers`).
    let answers: OopsAnswers
    let onDone: () -> Void

    /// Documentary-toned status, driven by the pipeline phase. Only Stage A (writing the story)
    /// is shown here — the moment the story is ready we step inside and the paintings stream
    /// onto the walls, so this screen no longer lingers through the slow image phase.
    private var statusText: String {
        switch appState.museumGenerator.phase {
        case .idle, .writing: return "see what others created here:"
        case .painting:       return "Stepping inside…"
        case .ready:          return "Stepping inside…"
        case .failed:         return "Opening the doors…"
        }
    }

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    BuildingMuseumHeader(size: 34)
                    Text(statusText)
                        .oopsSub(25)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                        .id(statusText)              // re-identity each stage so it crossfades
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.5), value: statusText)
                // A gallery of worlds previous visitors generated, flipping by while this
                // visitor's own world is built — the frame + label box hold still, only the
                // photo inside slides. Fills the otherwise-empty ~30s build wait.
                WoodenFrameSlideshow()
            }
        }
        .task { await runGeneration() }
    }

    /// Runs **Stage A only** of the Curator pipeline (the story), then enters the museum
    /// immediately. Stage B (the five paintings) keeps running in the background on the
    /// AppState-owned `museumGenerator`, and the immersive gallery streams each painting onto
    /// its wall as it lands. `galleryImages` is seeded with the beat-ordered placeholders so the
    /// walls start neutral and "develop" in. On any failure the run degrades gracefully
    /// (story fails → no narration + bundled placeholders) but the flow always completes, so the
    /// user is never trapped.
    private func runGeneration() async {
        let museumAnswers = MuseumAnswers(oops: answers)
        appState.museumAnswers = museumAnswers
        appState.museumGenerator.reset()                  // fresh run (clears any prior paint task)
        await appState.museumGenerator.generateStory(museumAnswers)   // awaits Stage A only
        appState.museumStory   = appState.museumGenerator.story
        appState.galleryImages = appState.museumGenerator.orderedGalleryImages()
        onDone()
    }
}

/// "Building your world" with an animated trailing ellipsis. All three dots always occupy
/// space (so the title never shifts); they fade in 1 → 2 → 3 on a timer to signal ongoing work.
private struct BuildingMuseumHeader: View {
    let size: CGFloat
    @State private var visible = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            Text("Building your world")
            HStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { i in
                    Text(".").opacity(i < visible ? 1 : 0.18)
                }
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(.white)
        .onReceive(timer) { _ in visible = visible % 3 + 1 }
    }
}

// MARK: - Previews

#Preview("Generating") {
    GeneratingScreen(answers: OopsAnswers(quizText: ["q3": "a world-class ballerina"]), onDone: {})
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

            Button { ButtonClick.play(); onExit() } label: {
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
        Button { ButtonClick.play(); performExit() } label: {
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
    @State private var isExiting = false
    @State private var showSettings = false

    var body: some View {
        // Bottom-bar styled control strip. visionOS has no host window to hang a real
        // `.ornament` on in full immersion, so we emulate the bottom toolbar with a slim window
        // + a settings popover. Resting state is just: ⋯ Settings · Leave world.
        HStack(spacing: 14) {
            Button { ButtonClick.play(); showSettings.toggle() } label: {
                Label("Settings", systemImage: "ellipsis")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { settingsPopover }

            // The forward/turn pad lives in the bar (not the popover) so it stays reachable while
            // walking. Shown only when enabled in settings; the gamepad is the default.
            if appState.museumSettings.showMovePad {
                SplatMovePad()
            }

            Button { ButtonClick.play(); leave(resume: .reflection) } label: {
                Label("Leave world", systemImage: "chevron.left")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExiting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // Single teardown path: any exit (button, gamepad, Digital Crown, system close) flips
        // `immersiveWorldOpen` false via `ImmersiveWorldView.onDisappear`; clean up here so no
        // floating window is ever left orphaned.
        .onChange(of: appState.immersiveWorldOpen) { _, open in
            if !open { performTeardown() }
        }
        // Turning the audio guide off silences any narration already playing.
        .onChange(of: appState.museumSettings.audioGuideOn) { _, on in
            if !on { appState.museumConversation?.stop() }
        }
    }

    @ViewBuilder
    private var settingsPopover: some View {
        @Bindable var settings = appState.museumSettings
        VStack(alignment: .leading, spacing: 14) {
            Text(appState.museumStory == nil ? "Richards Art Gallery" : "Your Future Museum")
                .font(.headline)

            // While Stage B is still painting, reassure the visitor the walls are filling in.
            if appState.museumGenerator.phase == .painting {
                let landed = appState.museumGenerator.nodes.filter { $0.image != nil }.count
                let total = appState.museumGenerator.nodes.count
                Label("Paintings developing… \(landed)/\(total)", systemImage: "paintbrush.pointed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Audio guide", isOn: $settings.audioGuideOn)
            Toggle("Background music", isOn: $settings.musicOn)
            Toggle("Subtitles", isOn: $settings.subtitlesOn)
            Button {
                ButtonClick.play()
                openWindow(id: "museum-voice-orb")
                showSettings = false
            } label: {
                Label("Talk to the guide", systemImage: "message")
            }
            .buttonStyle(.plain)

            Divider()

            // Always-visible: walk speed scales all locomotion (gamepad + pad); height nudges the
            // viewpoint up/down live. Fixed-width labels so both sliders start at the same x and
            // their (both centred-by-default) thumbs line up.
            HStack(spacing: 10) {
                Text("Walk speed").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
                Slider(value: $settings.moveSpeed, in: 0.5...1.5)
            }
            HStack(spacing: 10) {
                Text("Height").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .leading)
                Slider(value: $settings.eyeHeight, in: -0.5...0.5)
            }
            Toggle("Show forward pad", isOn: $settings.showMovePad)

            // The closing question, handed back to the visitor (Future Museum only).
            if let decision = appState.museumStory?.decision_prompt, !decision.isEmpty {
                Divider()
                Text("The decision")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(decision)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button { ButtonClick.play(); leave(resume: .home) } label: {
                Label("Start over", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .disabled(isExiting)
        }
        .padding(20)
        .frame(width: 320)
    }

    /// Button exit: record the resume screen, dismiss the immersive space, then clean up the
    /// floating windows — all in one Task. Running `dismissWindow(self)` from a Task (a fresh
    /// runloop turn, after `await`) is what makes the self-dismiss actually take; doing it
    /// synchronously inside `onChange` lets visionOS drop it (the window stays orphaned).
    private func leave(resume: OopsScreen) {
        guard !isExiting else { return }
        isExiting = true
        appState.oopsResumeScreen = resume
        showSettings = false
        Task { @MainActor in
            await dismissImmersiveSpace()
            cleanup()
        }
    }

    /// Safety net for non-button exits (Digital Crown / system close): `immersiveWorldOpen`
    /// flipped false without `leave` running. The space is already gone, so just clean up —
    /// deferred to a Task so the self-dismiss isn't dropped.
    private func performTeardown() {
        guard !isExiting else { return }
        isExiting = true
        Task { @MainActor in cleanup() }
    }

    /// Tears down the shared Curator voice + floating panels and returns to the Oops flow.
    /// Idempotent via `isExiting`; always invoked from a Task so the window ops land.
    private func cleanup() {
        appState.museumConversation?.stop()
        appState.museumConversation = nil
        appState.worldParams = nil
        // Default to the reflection montage; Leave / Start-over set a screen already, so keep it.
        if appState.oopsResumeScreen == nil { appState.oopsResumeScreen = .reflection }
        appState.devActiveFeature = .oops
        // Reopen the dev-menu flow; its `onAppear` closes THIS control window + the voice orb on
        // return. A visionOS `Window` can't reliably dismiss itself (dismissWindow(self) and
        // `\.dismiss` both fail); a DIFFERENT window's `dismissWindow(id:)` is reliable.
        openWindow(id: "dev-menu")
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

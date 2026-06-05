import SwiftUI

// MARK: - Generating interstitial

/// Spinner + "Building your world…" with staged hint copy, then advances to the preview.
struct GeneratingScreen: View {
    let onDone: () -> Void

    /// Staged copy shown while "generating". Each stage fades into the next.
    private let stages = [
        "Reading your answers…",
        "Shaping the light and the space…",
        "Adding the finishing touches…",
    ]
    @State private var stage = 0

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)
            VStack(spacing: 38) {
                OopsSpinner()
                Text("Building your world…")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(stages[stage])
                    .oopsSub(20)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                    .id(stage)                       // re-identity each stage so it crossfades
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.5), value: stage)
        }
        .task { await runGeneration() }
    }

    /// Placeholder generation step: cycles the staged copy, then advances. When a real
    /// generation backend lands, replace the per-stage sleeps with the actual work —
    /// the `onDone()` completion contract stays the same.
    private func runGeneration() async {
        for i in stages.indices {
            withAnimation { stage = i }
            try? await Task.sleep(for: .seconds(1.1))
        }
        onDone()
    }
}

// MARK: - 08 · Preview

struct PreviewScreen: View {
    let onEnter: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            OopsPassthrough()

            HStack(alignment: .top, spacing: 56) {
                // left — image
                VStack(alignment: .leading, spacing: 26) {
                    Text("Preview of the World")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(OopsGlass.label1)
                    Image("oops_meadow")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 560, height: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 48, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }

                // right — copy
                VStack(alignment: .leading, spacing: 24) {
                    Text(OopsContent.previewTitle)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text(OopsContent.previewBody)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onEnter) {
                        HStack(spacing: 8) { Text("Enter Now"); Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(OopsButton())
                    .padding(.top, 8)
                    Button("Not quite right, try another", action: onRetry)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .underline()
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: 480, alignment: .leading)
            }
            .padding(56)
            .frame(maxWidth: 1180, maxHeight: 760)
            .oopsCard(cornerRadius: 44)
            .padding(.horizontal, 40)

            VStack { Spacer(); PageDots().padding(.bottom, 18) }
        }
    }
}

// MARK: - Previews (Generating + PreviewScreen — no AppState dependency)

#Preview("Generating") {
    GeneratingScreen(onDone: {})
        .preferredColorScheme(.dark)
}

#Preview("PreviewScreen") {
    PreviewScreen(onEnter: {}, onRetry: {})
        .preferredColorScheme(.dark)
}

// MARK: - 09 · World (hosts the existing 3D world)

/// iPad: "Enter Now" enters the existing 3D `WorldView` (parametric USDZ + voice
/// companion). A glass close control overlays the top-left to leave to the reflection
/// flow. (On visionOS the world is the fully-immersive 6DoF splat space, opened directly
/// from `OopsFlowView.enterWorld` — this container is not used there.)
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

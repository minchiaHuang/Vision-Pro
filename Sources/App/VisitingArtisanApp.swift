import SwiftUI
#if os(visionOS)
import CompositorServices
#endif
#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscape
    }
}
#endif

/// App entry point.
/// ⚠️ This replaces the VisitingArtisanApp.swift that Xcode generates by default
/// (paste this content over it).
@main
struct VisitingArtisanApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var appState = AppState()

    var body: some Scene {
        // `id: "dev-menu"` so the splat flow can dismiss/reopen this window when
        // entering/leaving the full-immersion world.
        WindowGroup(id: "dev-menu") {
            Group {
                // DEV: in-app launcher to test each feature. Swap to RootView() before shipping.
                DevMenuView()
            }
            .environment(appState)
        }
        // Drop the default visionOS window glass so screens with a clear passthrough
        // (e.g. the Oops opening) float their content directly over the room instead of on
        // a white glass panel. Screens that want a surface bring their own (WarmBackground,
        // oopsWindow/oopsCard).
        #if os(visionOS)
        .windowStyle(.plain)
        #endif

        #if os(visionOS)
        // visionOS only: the truly immersive ImmersiveSpace
        ImmersiveSpace(id: "world") {
            ImmersiveWorldView()
                .environment(appState)
        }

        // visionOS only: walkable Gaussian-splat world (CompositorServices). A
        // `SplatEntry` (`.spz` URL + upright flip) is passed as the space's value;
        // full immersion replaces the room.
        ImmersiveSpace(id: "splat", for: SplatEntry.self) { $entry in
            CompositorLayer(configuration: SplatLayerConfiguration()) { layerRenderer in
                if let entry {
                    SplatVisionRenderer.startRendering(layerRenderer,
                                                       splatURL: entry.url,
                                                       flipUpsideDown: entry.flipUpsideDown)
                }
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        // visionOS only: tiny floating window shown while a splat world is open. The
        // full-immersion CompositorLayer can't host SwiftUI controls, so load progress
        // and the only way back out live here. A single `Window` (not `WindowGroup`) so
        // re-entering a world can never stack duplicate control panels.
        Window("Splat World", id: "splat-controls") {
            SplatExitControls()
        }
        .defaultSize(width: 360, height: 170)
        .windowResizability(.contentSize)
        // This window is opened only while a splat space is live; never restore it on
        // launch, or visionOS resurrects a stale panel stuck on an idle session.
        .restorationBehavior(.disabled)

        // visionOS only: the Oops flow's counterpart to `splat-controls`. Shown while the
        // Oops 6DoF splat world is open; hosts load progress, hold-to-move controls, and
        // an exit that returns to the Oops reflection flow. A single `Window` so
        // re-entering the world can't stack duplicate panels.
        Window("World", id: "oops-world-controls") {
            OopsWorldControls()
                .environment(appState)
        }
        .defaultSize(width: 380, height: 340)
        .windowResizability(.contentSize)
        // This window is opened only while the Oops splat world is live; never restore it
        // on launch, or visionOS resurrects a stale panel stuck on an idle session.
        .restorationBehavior(.disabled)

        // visionOS only: floating controls panel for the Oops art gallery world. Shown while
        // the RealityKit `world` ImmersiveSpace is open from the Oops flow. A single `Window`
        // so re-entering the gallery can't stack duplicate panels.
        Window("Art Gallery Controls", id: "oops-gallery-controls") {
            OopsGalleryControls()
                .environment(appState)
        }
        .defaultSize(width: 340, height: 220)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        // visionOS only: floating AI voice companion — a vertical glass pill (X · orb · replay).
        // .plain style lets the Capsule background show through instead of the default glass rect.
        // Invisible while the splat loads (Color.clear body); pill appears once SplatSession is .ready.
        Window("AI Guide", id: "oops-voice-orb") {
            OopsVoiceOrbView()
                .environment(appState)
        }
        .defaultSize(width: 200, height: 460)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        // .plain removed — it breaks visionOS input routing (eye-gaze hit testing fails on
        // plain-style windows in full immersion). Capsule is a visual element inside the glass rect.
        .defaultWindowPlacement { _, context in
            // Place trailing the world-controls panel (which opens just before this window).
            if let controls = context.windows.first(where: { $0.id == "oops-world-controls" }) {
                return WindowPlacement(.trailing(controls))
            }
            return WindowPlacement()
        }

        // visionOS only: the Future Museum's floating Curator voice — shown while the museum
        // gallery ImmersiveSpace is open. Drives the shared `AppState.museumConversation`
        // (push-to-talk), placed trailing the gallery controls panel.
        Window("Museum Guide", id: "museum-voice-orb") {
            MuseumVoiceOrbView()
                .environment(appState)
        }
        .defaultSize(width: 200, height: 420)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { _, context in
            if let controls = context.windows.first(where: { $0.id == "oops-gallery-controls" }) {
                return WindowPlacement(.trailing(controls))
            }
            return WindowPlacement()
        }

        // visionOS only: floating speech-to-text orb shown beside the Quiz screen so the user can
        // speak their answers instead of typing. Pure on-device STT (no AI voice). Opened while the
        // Oops flow is on the `.quiz` screen; writes into the shared `AppState.quizVoice`.
        Window("Answer by Voice", id: "quiz-voice-orb") {
            QuizVoiceOrbView()
                .environment(appState)
        }
        .defaultSize(width: 290, height: 460)   // TEMP larger to fit the dev status readout
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        #endif
    }
}

#if os(visionOS)
/// The floating panel shown while a splat immersive space is open. Two states, driven
/// by `SplatSession.shared`:
/// - **Loading**: estimated percentage + phase label while the `.spz` decodes (the
///   full-immersion view is otherwise just black until the scene is ready).
/// - **Ready / failed**: the "Exit world" button (the inverse of `SplatLibraryView.enter`).
///
/// Exit has one path, `performExit`, reached two ways: tapping the button, or the
/// gamepad ☰ button (which sets `session.exitRequested`, observed here). Routing the
/// gamepad through this window is what lets the exit "follow" the user — the window owns
/// `dismissImmersiveSpace`, the render thread can't call it.
private struct SplatExitControls: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var session = SplatSession.shared
    /// Guards `performExit` so the button tap and the gamepad request can't double-fire.
    @State private var isExiting = false

    var body: some View {
        VStack(spacing: 16) {
            switch session.phase {
            case .ready:
                SplatManipulatePad() // TEMP: simulator gesture backdoor — remove after device test
                exitButton
                Text("或按手把 ☰ 離開")
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
        // A panel that finds the session idle has no world to show (e.g. a scene visionOS
        // tried to restore). Confirm it stays idle through the open race, then dismiss.
        .task(id: session.phase) {
            guard session.phase == .idle else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if session.phase == .idle { dismissWindow(id: "splat-controls") }
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
            Label("Exit world", systemImage: "chevron.left")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isExiting)
    }

    /// Close the immersive space, bring the dev-menu window back, dismiss this window,
    /// and reset the session. Shared by the button tap and the gamepad ☰ request.
    private func performExit() {
        guard !isExiting else { return }
        isExiting = true
        Task {
            await dismissImmersiveSpace()
            SplatModelManipulation.shared.reset()
            openWindow(id: "dev-menu")
            dismissWindow(id: "splat-controls")
            session.reset()
        }
    }
}
#endif

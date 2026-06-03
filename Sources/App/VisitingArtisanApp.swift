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

        // visionOS only: DEV first-person walk-in for a USDZ model imported from the
        // Files app (matches the iPad USDZ viewer). The model's file URL is the value.
        ImmersiveSpace(id: "usdz", for: URL.self) { $url in
            if let url {
                ImmersiveUSDZView(modelURL: url)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
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
            default:
                loadingBody
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .onChange(of: session.exitRequested) { _, requested in
            if requested { performExit() }
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
            openWindow(id: "dev-menu")
            dismissWindow(id: "splat-controls")
            session.reset()
        }
    }
}
#endif

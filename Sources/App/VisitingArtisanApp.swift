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
    #if os(visionOS)
    // Shared source of truth for the one allowed Immersive Space (see ImmersiveSpaceController).
    @State private var spaces = ImmersiveSpaceController()
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                // DEV: in-app launcher to test each feature. Swap to RootView() before shipping.
                DevMenuView()
            }
            .environment(appState)
            #if os(visionOS)
            .environment(spaces)
            #endif
        }

        #if os(visionOS)
        // visionOS only: the truly immersive ImmersiveSpace
        ImmersiveSpace(id: "world") {
            ImmersiveWorldView()
                .environment(appState)
        }

        // visionOS only: walkable Gaussian-splat world (CompositorServices). The
        // `.spz` URL is passed as the space's value; full immersion replaces the room.
        ImmersiveSpace(id: "splat", for: URL.self) { $url in
            CompositorLayer(configuration: SplatLayerConfiguration()) { layerRenderer in
                if let url {
                    SplatVisionRenderer.startRendering(layerRenderer, splatURL: url)
                }
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        // visionOS only: DEV first-person walk-in for a bundled USDZ model (matches the
        // iPad USDZ viewer). The model name is passed as the space's value.
        ImmersiveSpace(id: "usdz", for: String.self) { $name in
            ImmersiveUSDZView(modelName: name ?? USDZDebug.models[0])
        }
        .immersionStyle(selection: .constant(.full), in: .full)
        #endif
    }
}

#if os(visionOS)
/// Single source of truth for the one allowed visionOS Immersive Space.
/// Injected at app root (see `spaces` above) so every view shares the same
/// "what's open" state, preventing the "Unable to present another Immersive
/// Space…" warning when switching spaces across different screens.
///
/// `openImmersiveSpace` / `dismissImmersiveSpace` are SwiftUI environment
/// actions only available inside a `View`, so callers pass the typed open/
/// dismiss closures (capturing their own value + environment actions). The
/// controller stays free of environment + value-type coupling and only owns
/// the guard + shared state.
@MainActor @Observable
final class ImmersiveSpaceController {
    /// "world", "splat", "usdz", or nil. Global truth, shared via environment.
    private(set) var currentSpaceID: String?
    private(set) var isTransitioning = false

    /// Dismiss any open space, then open `id`. Guarded so only one space is
    /// ever requested at a time.
    func present(id: String,
                 dismiss: () async -> Void,
                 open: () async -> OpenImmersiveSpaceAction.Result) async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        if currentSpaceID != nil {
            await dismiss()
            currentSpaceID = nil
        }
        if case .opened = await open() { currentSpaceID = id }
    }

    /// Dismiss the currently-open space (no-op if none).
    func dismiss(_ dismiss: () async -> Void) async {
        guard !isTransitioning, currentSpaceID != nil else { return }
        isTransitioning = true
        await dismiss()
        currentSpaceID = nil
        isTransitioning = false
    }
}
#endif

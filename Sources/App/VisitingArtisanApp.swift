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
        WindowGroup {
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
        #endif
    }
}

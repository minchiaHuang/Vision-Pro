import SwiftUI
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

/// App 進入點。
/// ⚠️ 這支取代 Xcode 預設產生的 VisitingArtisanApp.swift（把內容貼過去）。
@main
struct VisitingArtisanApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }

        #if os(visionOS)
        // visionOS 專用：真沉浸的 ImmersiveSpace
        ImmersiveSpace(id: "world") {
            ImmersiveWorldView()
                .environment(appState)
        }
        #endif
    }
}

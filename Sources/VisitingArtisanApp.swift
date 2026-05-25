import SwiftUI

/// App 進入點。
/// ⚠️ 這支取代 Xcode 預設產生的 VisitingArtisanApp.swift（把內容貼過去）。
@main
struct VisitingArtisanApp: App {
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

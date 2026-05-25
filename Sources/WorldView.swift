import SwiftUI

/// 顯示結果世界。平台分流：
/// - iOS/iPadOS：直接全螢幕 360° 環視
/// - visionOS：一個 window，按鈕開 ImmersiveSpace 進真沉浸
struct WorldView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        #if os(visionOS)
        VisionWorldPanel()
        #else
        iOSWorldView()
        #endif
    }
}

#if os(visionOS)
import SwiftUI

/// visionOS：控制面板，開/關 ImmersiveSpace。
struct VisionWorldPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 20) {
            Text(appState.world?.title ?? "Your world")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if let blurb = appState.world?.blurb, !blurb.isEmpty {
                Text(blurb).foregroundStyle(.secondary)
            }
            Button(isOpen ? "Leave the world" : "Step into your world") {
                Task {
                    if isOpen {
                        await dismissImmersiveSpace()
                        isOpen = false
                    } else {
                        if case .opened = await openImmersiveSpace(id: "world") {
                            isOpen = true
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Start over") { appState.restart() }
                .buttonStyle(.bordered)
        }
        .padding(40)
    }
}
#else

/// iOS/iPadOS：全螢幕 360° 環視 + 疊字。
struct iOSWorldView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if let world = appState.world {
                Immersive360View(world: world)
                    .ignoresSafeArea()
            }
            VStack {
                Spacer()
                Text(appState.world?.title ?? "")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Start over") { appState.restart() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
            }
        }
    }
}
#endif

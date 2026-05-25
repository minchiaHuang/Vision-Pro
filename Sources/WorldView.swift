import SwiftUI

/// Shows the resolved world.
/// - iOS/iPadOS: full-screen 360-degree view.
/// - visionOS: panel controls that open the immersive space.
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

/// visionOS panel for opening and closing the immersive space.
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

/// iOS/iPadOS full-screen 360-degree view with a readable result overlay.
struct iOSWorldView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if let world = appState.world {
                Immersive360View(world: world)
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Text(appState.world?.title ?? "")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                        .multilineTextAlignment(.center)

                    if let blurb = appState.world?.blurb, !blurb.isEmpty {
                        Text(blurb)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .shadow(radius: 8)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: 560)

                Button("Start over") { appState.restart() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
#endif

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
        VStack(spacing: 22) {
            Text("Your world is ready")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(appState.world?.title ?? "Your world")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            if let blurb = appState.world?.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
            .buttonStyle(PrimaryPillButtonStyle())

            Button("Start over") { appState.restart() }
                .buttonStyle(SecondaryPillButtonStyle())
        }
        .frame(maxWidth: 520)
        .padding(44)
    }
}
#else

/// iOS/iPadOS full-screen 360-degree view with a readable result overlay.
struct iOSWorldView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                if let world = appState.world {
                    Immersive360View(world: world)
                        .ignoresSafeArea()
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(isLandscape ? 0.74 : 0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: isLandscape ? 10 : 14) {
                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Text(appState.world?.title ?? "")
                            .font((isLandscape ? Font.title3 : Font.title2).weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 8)
                            .multilineTextAlignment(.center)

                        if let blurb = appState.world?.blurb, !blurb.isEmpty {
                            Text(blurb)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.88))
                                .shadow(radius: 8)
                                .multilineTextAlignment(.center)
                                .lineLimit(isLandscape ? 2 : 3)
                        }
                    }
                    .frame(maxWidth: isLandscape ? 680 : 560)

                    Button("Start over") { appState.restart() }
                        .buttonStyle(PrimaryPillButtonStyle())
                }
                .padding(.horizontal, isLandscape ? 32 : 24)
                .padding(.bottom, isLandscape ? 28 : 44)
            }
        }
    }
}
#endif

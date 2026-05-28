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

    /// Which ImmersiveSpace is currently open (if any).
    /// "world" = 3DoF skybox, "world_3d" = 6DoF USDZ spike.
    @State private var openSpaceID: String? = nil

    private var skyboxLabel: String {
        openSpaceID == "world" ? "Leave the world" : "Step into your world"
    }
    private var spikeLabel: String {
        openSpaceID == "world_3d" ? "Leave 6DoF" : "View in 6DoF (spike)"
    }

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

            Button(skyboxLabel) {
                Task { await toggle(spaceID: "world") }
            }
            .buttonStyle(PrimaryPillButtonStyle())

            Button(spikeLabel) {
                Task { await toggle(spaceID: "world_3d") }
            }
            .buttonStyle(SecondaryPillButtonStyle())

            Button("Start over") {
                Task {
                    if openSpaceID != nil {
                        await dismissImmersiveSpace()
                        openSpaceID = nil
                    }
                    appState.restart()
                }
            }
            .buttonStyle(SecondaryPillButtonStyle())
        }
        .frame(maxWidth: 520)
        .padding(44)
        .task {
            // Dev shortcut: auto-open the 6DoF ImmersiveSpace once when the
            // panel first appears. Small delay lets the SwiftUI scene env
            // wire `openImmersiveSpace` before we call it.
            guard DebugConfig.autoOpenSpike, openSpaceID == nil else { return }
            try? await Task.sleep(for: .milliseconds(100))
            await toggle(spaceID: "world_3d")
        }
    }

    /// Toggles between the named ImmersiveSpace and the windowed panel.
    /// If a different ImmersiveSpace is already open, dismiss it first —
    /// only one ImmersiveSpace can be presented at a time on visionOS.
    private func toggle(spaceID: String) async {
        if openSpaceID == spaceID {
            await dismissImmersiveSpace()
            openSpaceID = nil
            return
        }

        if openSpaceID != nil {
            await dismissImmersiveSpace()
            openSpaceID = nil
        }

        if case .opened = await openImmersiveSpace(id: spaceID) {
            openSpaceID = spaceID
        }
    }
}
#else

/// iOS/iPadOS full-screen 360-degree view with a readable result overlay.
struct iOSWorldView: View {
    @Environment(AppState.self) private var appState
    @State private var show6DoFSpike = false

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

                    Button("View in 6DoF (spike)") { show6DoFSpike = true }
                        .buttonStyle(SecondaryPillButtonStyle())
                        .disabled(appState.world == nil)

                    Button("Start over") { appState.restart() }
                        .buttonStyle(PrimaryPillButtonStyle())
                }
                .padding(.horizontal, isLandscape ? 32 : 24)
                .padding(.bottom, isLandscape ? 28 : 44)
            }
        }
        .fullScreenCover(isPresented: $show6DoFSpike) {
            if let world = appState.world {
                Scene3DView(world: world)
            }
        }
        .onAppear {
            // Dev shortcut: auto-jump into the 6DoF spike on first appearance.
            // No-op once the user has already toggled the spike for this run.
            if DebugConfig.autoOpenSpike && !show6DoFSpike {
                show6DoFSpike = true
            }
        }
    }
}
#endif

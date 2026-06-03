import SwiftUI

// MARK: - Generating interstitial

/// Spinner + "Building your world…" with staged hint copy, then advances to the preview.
struct GeneratingScreen: View {
    let onDone: () -> Void

    /// Staged copy shown while "generating". Each stage fades into the next.
    private let stages = [
        "Reading your answers…",
        "Shaping the light and the space…",
        "Adding the finishing touches…",
    ]
    @State private var stage = 0

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)
            VStack(spacing: 38) {
                OopsSpinner()
                Text("Building your world…")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(stages[stage])
                    .oopsSub(20)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                    .id(stage)                       // re-identity each stage so it crossfades
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.5), value: stage)
        }
        .task { await runGeneration() }
    }

    /// Placeholder generation step: cycles the staged copy, then advances. When a real
    /// generation backend lands, replace the per-stage sleeps with the actual work —
    /// the `onDone()` completion contract stays the same.
    private func runGeneration() async {
        for i in stages.indices {
            withAnimation { stage = i }
            try? await Task.sleep(for: .seconds(1.1))
        }
        onDone()
    }
}

// MARK: - 08 · Preview

struct PreviewScreen: View {
    let onEnter: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            OopsPassthrough()

            HStack(alignment: .top, spacing: 56) {
                // left — image
                VStack(alignment: .leading, spacing: 26) {
                    Text("Preview of the World")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(OopsGlass.label1)
                    Image("oops_meadow")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 560, height: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 48, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }

                // right — copy
                VStack(alignment: .leading, spacing: 24) {
                    Text(OopsContent.previewTitle)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text(OopsContent.previewBody)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onEnter) {
                        HStack(spacing: 8) { Text("Enter Now"); Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(OopsButton())
                    .padding(.top, 8)
                    Button("Not quite right, try another", action: onRetry)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .underline()
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: 480, alignment: .leading)
            }
            .padding(56)
            .frame(maxWidth: 1180, maxHeight: 760)
            .oopsCard(cornerRadius: 44)
            .padding(.horizontal, 40)

            HStack { Spacer(); SideBar().padding(.trailing, 28) }
            VStack { Spacer(); PageDots().padding(.bottom, 18) }
        }
    }
}

// MARK: - 09 · World (hosts the existing 3D world)

/// Per the user's decision, "Enter Now" enters the existing 3D `WorldView` (parametric
/// USDZ + voice companion) rather than the prototype's 2D room-hotspot scene. A glass
/// close control overlays the top-left to leave to the Exit screen.
struct OopsWorldContainer: View {
    let onExit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorldView(onExit: onExit)
                .ignoresSafeArea()

            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .padding(.top, 28)
            .accessibilityLabel("Leave world")
        }
    }
}

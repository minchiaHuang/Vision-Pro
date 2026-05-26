import SwiftUI

/// Experimental, standalone screen to validate the World Labs API end to end.
/// Decoupled from the quiz flow: enter a prompt, generate, then view the panorama.
struct WorldLabsTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = WorldLabsService()
    @State private var prompt = "A calm sunlit room with warm wood, plants, and soft morning light"

    var body: some View {
        ZStack {
            switch service.status {
            case .ready(let image):
                worldView(image)
            default:
                form
            }
        }
    }

    // MARK: - Input / progress

    private var form: some View {
        VStack(spacing: 22) {
            Text("World Labs · Experimental")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Generate a world from a prompt")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            TextField("Describe a world", text: $prompt, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)

            statusBody

            HStack(spacing: 14) {
                Button("Back") { dismiss() }
                    .buttonStyle(.bordered)

                Button(isBusy ? "Generating…" : "Generate world") {
                    Task { await service.run(prompt: prompt) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: 560)
        .padding(32)
    }

    @ViewBuilder
    private var statusBody: some View {
        switch service.status {
        case .idle:
            Text("Generation takes ~5 minutes and uses paid API credits.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .generating(let progress):
            VStack(spacing: 10) {
                ProgressView(value: Double(progress), total: 100)
                Text("Building your world… \(progress)%  (~5 min)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .downloading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Downloading panorama…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        case .ready:
            EmptyView()
        }
    }

    private var isBusy: Bool {
        switch service.status {
        case .generating, .downloading: return true
        default: return false
        }
    }

    // MARK: - World display

    @ViewBuilder
    private func worldView(_ image: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            #if os(visionOS)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            #else
            Immersive360View(world: WorldCatalog.fallback, overrideImage: image)
                .ignoresSafeArea()
            #endif

            Button("Back") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 32)
        }
    }
}

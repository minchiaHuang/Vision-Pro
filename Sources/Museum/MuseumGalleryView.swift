import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Drives the two-stage pipeline and holds its progress. `@Observable` so the gallery
/// reacts to the phase change and to each `GeneratedNode`'s image landing.
@MainActor
@Observable
final class MuseumGenerator {
    enum Phase: Equatable {
        case idle           // nothing run yet
        case writing        // Stage A — the Curator is writing the story
        case painting       // Stage B — images are generating (cards stream in)
        case ready          // all five resolved (some may have failed individually)
        case failed(String) // Stage A failed — nothing to show
    }

    private(set) var phase: Phase = .idle
    private(set) var story: MuseumStory?
    private(set) var nodes: [GeneratedNode] = []

    private let curator = CuratorService()
    private let images = ImageGenerationService()

    /// Nonisolated so the (non-`@MainActor`) `AppState` can create one as a stored-property
    /// default. Every stored default above is actor-agnostic, so this is safe.
    nonisolated init() {}

    /// Holds the background Stage B (image painting) task so it keeps running after the caller
    /// has moved on. The Oops flow enters the museum the moment the story is ready, which tears
    /// down the dev-menu window — and thus `GeneratingScreen`. By owning the task here (not in a
    /// view's `.task`), Stage B survives that teardown and keeps streaming images onto the walls.
    private var paintTask: Task<Void, Never>?

    /// Stage A only. Writes the story, seeds the (image-less) `nodes`, flips to `.painting`,
    /// and kicks off Stage B **in the background without awaiting it** — so the caller can enter
    /// the museum the instant the story is ready and let each painting stream onto its wall as it
    /// lands. Returns once the story resolves (or `.failed`).
    func generateStory(_ answers: MuseumAnswers) async {
        guard phase == .idle else { return }
        phase = .writing

        let result: MuseumStory
        do {
            result = try await curator.generate(answers)
        } catch {
            phase = .failed(CuratorService.describe(error))
            return
        }

        story = result
        nodes = result.nodes.map { GeneratedNode(node: $0) }
        phase = .painting
        paintTask = Task { [weak self] in await self?.paintImages() }
    }

    /// Stage B. Paints all five beats in parallel; each `GeneratedNode` updates as its image
    /// arrives (`@Observable`, so a bound view/world re-textures live). Flips to `.ready` once
    /// every request has resolved (some may have failed individually).
    private func paintImages() async {
        await withTaskGroup(of: Void.self) { group in
            let images = self.images
            for gen in nodes {
                group.addTask {
                    do {
                        let data = try await images.image(forPrompt: gen.node.image_prompt)
                        await MainActor.run { gen.image = data }
                    } catch {
                        await MainActor.run { gen.failed = true }
                    }
                }
            }
        }
        phase = .ready
    }

    /// Runs both stages and awaits completion (Stage A then Stage B). Used by the flat
    /// `MuseumGalleryView`, whose behaviour is unchanged — it still waits for all five images.
    func run(_ answers: MuseumAnswers) async {
        await generateStory(answers)
        await paintTask?.value
    }

    /// Re-paints a single beat whose image failed (or never landed) — driven by the in-world
    /// "tap to retry" on a failed picture frame. Clears `failed`, fetches the image again, and on
    /// success sets `image` (the gallery's signature watcher then re-textures that wall on its own).
    func retry(_ gen: GeneratedNode) {
        guard gen.image == nil else { return }
        gen.failed = false
        Task { @MainActor in
            do { gen.image = try await images.image(forPrompt: gen.node.image_prompt) }
            catch { gen.failed = true }
        }
    }

    /// Beat-ordered images for the gallery walls — a fixed slot per beat, so frame *i* always
    /// shows beat *i*. A beat whose image failed (or hasn't landed) keeps its slot with a
    /// neutral placeholder, so the image-on-wall ↔ per-beat-narration mapping never shifts.
    func orderedGalleryImages() -> [UIImage] {
        nodes.map { gen in
            if let data = gen.image, let ui = UIImage(data: data) { return ui }
            return Self.placeholderImage
        }
    }

    /// A plain dark panel shown when a beat's image is missing (failed / not yet generated).
    private static let placeholderImage: UIImage = {
        let size = CGSize(width: 1024, height: 1024)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }()

    func reset() {
        paintTask?.cancel()
        paintTask = nil
        phase = .idle
        story = nil
        nodes = []
    }
}

/// Flat gallery for the pipeline-only milestone: the persona, a horizontal row of beat
/// cards (each streaming its image in), and the closing decision card. Fully SwiftUI, so
/// it runs on the Vision Pro simulator without a headset.
struct MuseumGalleryView: View {
    let generator: MuseumGenerator
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            switch generator.phase {
            case .idle, .writing:
                status("Writing your story…")
            case .failed(let message):
                failure(message)
            case .painting, .ready:
                content
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: States

    private func status(_ text: String) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(.white)
            Text(text).font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundStyle(.yellow.opacity(0.9))
            Text(message)
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: 520)
            Button("Start over") { ButtonClick.play(); onRestart() }.buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let story = generator.story {
                    Text(story.persona)
                        .font(.system(size: 30, weight: .semibold))
                        .padding(.horizontal, 40)
                        .padding(.top, 40)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(generator.nodes) { gen in
                            BeatCard(gen: gen)
                        }
                        if let story = generator.story {
                            DecisionCard(text: story.decision_prompt, onRestart: onRestart)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

// MARK: - Cards

/// One beat: the (streaming) image on top, narration below.
private struct BeatCard: View {
    let gen: GeneratedNode

    private var isWarm: Bool { gen.node.tone == "warm" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))

                if let data = gen.image, let ui = platformImage(data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else if gen.failed {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.system(size: 32))
                        Text(gen.node.beat)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 360, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isWarm ? Color.orange.opacity(0.5) : Color.white.opacity(0.12),
                                  lineWidth: 1)
            )

            Text(gen.node.narration)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 360, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 360)
    }
}

/// The closing card: the decision prompt that hands the choice back to the visitor.
private struct DecisionCard: View {
    let text: String
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("The decision")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Start over") { ButtonClick.play(); onRestart() }.buttonStyle(.bordered).tint(.white)
        }
        .padding(24)
        .frame(width: 360, height: 240 + 12 + 60, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

#if canImport(UIKit)
private func platformImage(_ data: Data) -> UIImage? { UIImage(data: data) }
#else
private func platformImage(_ data: Data) -> Image? { nil }
#endif

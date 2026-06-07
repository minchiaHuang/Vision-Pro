import Foundation
import UIKit

/// Generates a short Hero's-Journey image series from a user's goal via the OpenAI Images API,
/// for display in the art gallery's wall frames.
///
/// v1 keeps a single network dependency (image generation) — the 5 scene prompts are built by a
/// deterministic template (`heroJourneyPrompts`), so there's no second LLM call to fail. A future
/// version can author the prompts with a chat model to generalise to any goal.
///
/// Networking mirrors the app's other services (`ConversationService`, `WorldLabsService`): a
/// plain `URLSession` POST with a Bearer key and Codable request/response. If the key is empty or
/// every image fails, it returns whatever succeeded (possibly `[]`) so the caller degrades
/// gracefully to the bundled placeholders.
enum OpenAIImageService {

    // This account exposes the gpt-image-1 family (no dall-e). Using the cheaper -mini for
    // testing; swap to "gpt-image-1" for higher quality. The family always returns b64 and
    // rejects `response_format`, so that flag is off. (dall-e-3 would need it back on.)
    private static let model = "gpt-image-1-mini"
    private static let usesResponseFormat = false
    private static let size = "1024x1024"
    private static let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!

    enum ImageError: Error { case missingKey, badResponse, api(status: Int, body: String), decode }

    /// Builds the 5 Hero's-Journey prompts from `goal` and generates one image per beat,
    /// sequentially (to stay under image rate limits). `onProgress(done, total)` fires before
    /// each beat and once more at completion. Returns the images that succeeded, in beat order.
    static func generateJourney(goal: String,
                                onProgress: @escaping @MainActor (Int, Int) -> Void) async -> [UIImage] {
        let prompts = heroJourneyPrompts(goal: goal)
        var images: [UIImage] = []
        for (index, prompt) in prompts.enumerated() {
            await onProgress(index, prompts.count)
            do {
                images.append(try await generateImage(prompt: prompt))
            } catch {
                #if DEBUG
                print("[OpenAIImageService] scene \(index + 1)/\(prompts.count) failed: \(error)")
                #endif
            }
        }
        await onProgress(prompts.count, prompts.count)
        saveToDisk(images)
        return images
    }

    /// Writes the generated series to `Documents/GalleryJourney/scene_01.png …` so the images can
    /// be inspected outside the app (the folder is reset each run). The path is logged in DEBUG.
    /// Best-effort: failures are ignored and never block the flow.
    @discardableResult
    static func saveToDisk(_ images: [UIImage]) -> URL? {
        guard !images.isEmpty else { return nil }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("GalleryJourney", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, image) in images.enumerated() {
            guard let data = image.pngData() else { continue }
            try? data.write(to: dir.appendingPathComponent(String(format: "scene_%02d.png", index + 1)))
        }
        #if DEBUG
        print("[OpenAIImageService] saved \(images.count) image(s) to \(dir.path)")
        #endif
        return dir
    }

    /// The 5 ordered scene prompts: Ordinary world → Call → Trials → Transformation → Mastery,
    /// each interpolating `goal` and sharing a style/consistency preamble.
    static func heroJourneyPrompts(goal: String) -> [String] {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = "Cinematic, photorealistic, soft natural light, the same single protagonist "
            + "throughout the whole series with a consistent face, body, and wardrobe, emotional "
            + "and inspiring, fine-art photography, vertical portrait composition. "
            + "No text, no captions, no watermark, no logos."
        let beats = [
            "Ordinary world: the protagonist at the very beginning of their path toward \(g), "
                + "in a humble everyday setting, quiet determination, a dream not yet realised.",
            "The call: the protagonist commits to pursuing \(g), taking the first real steps, "
                + "hopeful and a little daunted, beginning to train and prepare.",
            "Trials: the protagonist struggles and perseveres on the way to \(g) — hard practice, "
                + "setbacks, sweat and resilience, visibly growing stronger.",
            "Transformation: a breakthrough moment, the protagonist's skill and confidence "
                + "blossoming toward \(g), grace and mastery emerging.",
            "Mastery: the protagonist fully realised as \(g), at the triumphant peak, performing "
                + "with excellence on a grand stage, radiant and accomplished.",
        ]
        return beats.map { "\($0) \(style)" }
    }

    // MARK: - Networking

    private struct GenRequest: Encodable {
        let model: String
        let prompt: String
        let n: Int
        let size: String
        let response_format: String?   // omitted when nil (gpt-image-1)
    }

    private struct GenResponse: Decodable {
        struct Item: Decodable { let b64_json: String? }
        let data: [Item]
    }

    private static func generateImage(prompt: String) async throws -> UIImage {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { throw ImageError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenRequest(
            model: model, prompt: prompt, n: 1, size: size,
            response_format: usesResponseFormat ? "b64_json" : nil))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageError.api(status: http.statusCode,
                                 body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(GenResponse.self, from: data)
        guard let b64 = decoded.data.first?.b64_json,
              let bytes = Data(base64Encoded: b64),
              let image = UIImage(data: bytes) else { throw ImageError.decode }
        return image
    }
}

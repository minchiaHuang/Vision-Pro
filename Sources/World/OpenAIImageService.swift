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
    static func generateJourney(q3: String, q4: String, q5: String, q6: String,
                                onProgress: @escaping @MainActor (Int, Int) -> Void) async -> [UIImage] {
        print("[DEBUG] generateJourney called with q3: \(q3)")
        let prompts = await heroJourneyPrompts(q3: q3, q4: q4, q5: q5, q6: q6)
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
    static func heroJourneyPrompts(q3: String, q4: String, q5: String, q6: String) async -> [String] {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { return [] }
        let systemPrompt = """
           You are a visual storytelling expert specializing in silhouette-based fine art photography. Given a person's quiz answers about their inner life and aspirations, generate exactly 5 vivid, specific image generation prompts.

           Each prompt must describe a real, grounded scene that uses SILHOUETTE PHOTOGRAPHY STYLE — strong backlit compositions where objects and environments appear as dark silhouettes against dramatically bright, glowing backgrounds. No people, no faces, no portraits.

           Example of a good prompt: "A silhouette of an empty wooden chair beside a large window at golden hour, the chair and windowsill rendered as deep dark shapes against an intensely glowing amber and orange sky outside, dust particles floating in the light, wide cinematic composition, fine-art photography."

           The 5 scenes must represent:
           1. Where this person is right now — their current emotional state and daily reality
           2. The obstacle or fear that holds them back
           3. The turning point — a moment of shift or clarity
           4. Their ideal life in action — what it actually looks and feels like
           5. The thing they will never give up — their core love or value

           Rules:
           - SILHOUETTE STYLE: every scene must have a bright, luminous background with dark foreground elements — strong backlight is mandatory
           - No people, no faces, no text in the image
           - Fine-art photography style, high contrast, dramatic lighting
           - Each prompt should be 2-4 sentences
           - The background must always be bright and radiant — golden sunrise, glowing sunset, bright window light, moonlit sky, luminous fog, or bright open sky
           - Wide cinematic compositions showing full environments
           - Location type: one outdoor nature scene, one urban exterior, one minimalist indoor space, one abstract/surreal space, one transitional space (doorway, bridge, or path)
           - Time of day: each scene at a different time (dawn, morning, afternoon, dusk, night)
           - Color temperature: warm amber, cool blue, soft rose/pink, deep violet, bright white — one per scene, never repeated

           Return ONLY a JSON array of exactly 5 strings, nothing else. Example format:
           ["prompt one", "prompt two", "prompt three", "prompt four", "prompt five"]
           """

           let userMessage = """
           Q3 (ideal future): \(q3)
           Q4 (current self): \(q4)
           Q5 (biggest obstacle): \(q5)
           Q6 (thing they won't give up): \(q6)
           """

           let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
           var request = URLRequest(url: chatEndpoint)
           request.httpMethod = "POST"
           request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")

           let body: [String: Any] = [
               "model": "gpt-4o-mini",
               "messages": [
                   ["role": "system", "content": systemPrompt],
                   ["role": "user", "content": userMessage]
               ],
               "temperature": 0.8
           ]
           request.httpBody = try? JSONSerialization.data(withJSONObject: body)

           guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }

           struct ChatResponse: Decodable {
               struct Choice: Decodable {
                   struct Message: Decodable { let content: String }
                   let message: Message
               }
               let choices: [Choice]
           }

           guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
                 let content = decoded.choices.first?.message.content,
                 let jsonData = content.data(using: .utf8),
                 let prompts = try? JSONDecoder().decode([String].self, from: jsonData),
                 prompts.count == 5 else { return [] }

           return prompts
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

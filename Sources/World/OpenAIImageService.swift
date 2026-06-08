import Foundation
import UIKit

enum OpenAIImageService {

    private static let imageModel =  "gpt-image-1"
    private static let textModel = "gpt-4o-mini"
    private static let usesResponseFormat = false
    private static let size = "1024x1024"
    private static let imageEndpoint = URL(string: "https://api.openai.com/v1/images/generations")!
    private static let textEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    enum ImageError: Error { case missingKey, badResponse, api(status: Int, body: String), decode }

    // MARK: - Main entry point

    static func generateJourney(goal: String,
                                currentSelf: String = "",
                                obstacle: String = "",
                                wontGiveUp: String = "",
                                onProgress: @escaping @MainActor (Int, Int) -> Void) async -> [UIImage] {
        // Step 1: Generate 5 scene descriptions from GPT
        let prompts: [String]
        do {
            prompts = try await generateSceneDescriptions(
                goal: goal,
                currentSelf: currentSelf,
                obstacle: obstacle,
                wontGiveUp: wontGiveUp
            )
        } catch {
            #if DEBUG
            print("[OpenAIImageService] scene description generation failed: \(error)")
            #endif
            prompts = heroJourneyPrompts(goal: goal, currentSelf: currentSelf, obstacle: obstacle, wontGiveUp: wontGiveUp)
        }

        // Step 2: Generate all 5 images in parallel
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

    // MARK: - Step 1: GPT generates 5 scene descriptions

    private static func generateSceneDescriptions(goal: String,
                                                   currentSelf: String,
                                                   obstacle: String,
                                                   wontGiveUp: String) async throws -> [String] {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { throw ImageError.missingKey }

        let systemPrompt = """
        You are a visual storytelling expert. Given a person's quiz answers about their inner life and aspirations, generate exactly 5 vivid, specific image generation prompts.

        Each prompt must describe a real, grounded scene — a specific room, space, or environment — that emotionally represents one aspect of this person's inner world. No people, no faces, no portraits.

        Example of a good prompt: "A sunlit kitchen at 8am, a half-eaten breakfast on the table beside an open notebook, warm golden light streaming through a window onto a wooden floor. The space feels like someone who is just beginning to believe in themselves."

        The 5 scenes must represent:
        1. Where this person is right now — their current emotional state and daily reality
        2. The obstacle or fear that holds them back
        3. The turning point — a moment of shift or clarity
        4. Their ideal life in action — what it actually looks and feels like
        5. The thing they will never give up — their core love or value

        Rules:
        - Each prompt must be specific and cinematic, describing exact objects, lighting, time of day, atmosphere
        - No people, no faces, no text in the image
        - Photorealistic, fine-art photography style
        - Consistent warm, cinematic color palette across all 5 scenes
        - Each prompt should be 2-4 sentences
        - Each of the 5 scenes MUST be visually distinct — different locations, different times of day, different lighting and atmosphere. Never repeat the same type of space twice.
        - Scenes must be bright, open, and spacious — avoid dark, cramped, or claustrophobic spaces
        - Use natural daylight or warm golden light as the primary light source
        - Wide angle compositions showing full environments, not close-up corners
        - Scene 1 should feel like an everyday personal space (bedroom, desk, kitchen)
        - Scene 2 should feel like a more public or external space (gallery, street, library)
        - Scene 3 should feel like a transitional space (doorway, window, staircase, path)
        - Scene 4 should feel like an aspirational or professional space (studio, office, stage)
        - Scene 5 should feel like a deeply personal and quiet space (garden, corner of a room, a table with meaningful objects)

        Return ONLY a JSON array of exactly 5 strings, nothing else. Example format:
        ["prompt one", "prompt two", "prompt three", "prompt four", "prompt five"]
        """

        let userMessage = """
        Here are the person's answers:

        Q3 - Ideal future and who they want to become:
        \(goal)

        Q4 - How they describe their current self:
        \(currentSelf)

        Q5 - The biggest thing standing between them and their ideal self:
        \(obstacle)

        Q6 - What they are least willing to give up:
        \(wontGiveUp)

        Generate 5 scene prompts based on these answers.
        """

        let body: [String: Any] = [
            "model": textModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.8,
            "max_tokens": 1000
        ]

        var request = URLRequest(url: textEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageError.api(status: http.statusCode,
                                 body: String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ImageError.decode
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let promptData = cleaned.data(using: .utf8),
              let prompts = try? JSONDecoder().decode([String].self, from: promptData),
              prompts.count == 5 else {
            throw ImageError.decode
        }

        #if DEBUG
        print("[OpenAIImageService] GPT generated prompts:")
        prompts.enumerated().forEach { print("  Scene \($0.offset + 1): \($0.element)") }
        #endif

        return prompts
    }

    // MARK: - Fallback template prompts

    static func heroJourneyPrompts(goal: String,
                                   currentSelf: String = "",
                                   obstacle: String = "",
                                   wontGiveUp: String = "") -> [String] {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = currentSelf.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = obstacle.trimmingCharacters(in: .whitespacesAndNewlines)
        let keep = wontGiveUp.trimmingCharacters(in: .whitespacesAndNewlines)

        let style = "Cinematic, photorealistic, soft natural light, "
            + "wide environmental scene, immersive atmosphere, "
            + "consistent visual style and color palette across the series, "
            + "metaphorical and emotional, fine-art photography, landscape or interior composition. "
            + "No close-up portraits, no text, no captions, no watermark, no logos."

        let beats = [
            "A bright everyday personal space representing someone who \(current.isEmpty ? "is searching for direction" : current). No people.",
            "An open public space capturing the feeling of \(block.isEmpty ? "self-doubt and comparison" : block). No people.",
            "A transitional space — a doorway, window or path — where something is shifting. Warm light. No people.",
            "A bright aspirational space embodying the feeling of \(g). No people.",
            "A quiet personal space anchored by \(keep.isEmpty ? "a deep love for the process" : keep). Warm, earned. No people.",
        ]
        return beats.map { "\($0) \(style)" }
    }

    // MARK: - Save to disk

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

    // MARK: - Image generation

    private struct GenRequest: Encodable {
        let model: String
        let prompt: String
        let n: Int
        let size: String
        let response_format: String?
    }

    private struct GenResponse: Decodable {
        struct Item: Decodable {
            let b64_json: String?
            let url: String?
        }
        let data: [Item]
    }

    private static func generateImage(prompt: String) async throws -> UIImage {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { throw ImageError.missingKey }

        var request = URLRequest(url: imageEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenRequest(
            model: imageModel, prompt: prompt, n: 1, size: size,
            response_format: usesResponseFormat ? "b64_json" : nil))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ImageError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ImageError.api(status: http.statusCode,
                                 body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(GenResponse.self, from: data)
        guard let item = decoded.data.first else { throw ImageError.decode }

        if let urlString = item.url, let imageURL = URL(string: urlString) {
            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: imageData) else { throw ImageError.decode }
            return image
        } else if let b64 = item.b64_json,
                  let bytes = Data(base64Encoded: b64),
                  let image = UIImage(data: bytes) {
            return image
        } else {
            throw ImageError.decode
        }
    }
}

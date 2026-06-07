import Foundation

/// Stage B — the painter. Turns one beat's `image_prompt` into a PNG via the OpenAI
/// Images API (`/v1/images/generations`, model `gpt-image-2`) over plain `URLSession`.
/// Returns the decoded image bytes; the caller turns them into a `UIImage`.
///
/// A value type (`struct`) so it is `Sendable` and the gallery can fire all five image
/// requests concurrently from a `TaskGroup`.
struct ImageGenerationService {

    enum ImageError: Error { case missingKey, http(String), empty }

    /// Current flagship image model (per OpenAI's image API). Landscape frames fit the
    /// museum wall and are slightly cheaper than square at medium/high quality.
    private static let model = "gpt-image-2"

    func image(forPrompt prompt: String) async throws -> Data {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { throw ImageError.missingKey }

        let payload = Request(model: Self.model, prompt: prompt,
                              size: "1536x1024", quality: "medium",
                              output_format: "png", n: 1)

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw ImageError.http("HTTP \(http.statusCode): \(snippet)")
        }

        // gpt-image-2 returns base64 PNG (no URL form).
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.data.first?.b64_json,
              let imageData = Data(base64Encoded: b64) else {
            throw ImageError.empty
        }
        return imageData
    }

    private struct Request: Encodable {
        let model: String
        let prompt: String
        let size: String
        let quality: String
        let output_format: String
        let n: Int
    }

    private struct Response: Decodable {
        struct Item: Decodable { let b64_json: String }
        let data: [Item]
    }
}

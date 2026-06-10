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

        // quality "low" trades fidelity for speed/cost — the museum walls read fine at low and
        // it noticeably shortens the ~90s Stage B wait. Bump back to "medium" for hero shots.
        let payload = Request(model: Self.model, prompt: prompt,
                              size: "1536x1024", quality: "low",
                              output_format: "png", n: 1)

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)

        // Same shared retry path as the Curator: a transient 5xx / Cloudflare 520–524 or a
        // network blip is retried with backoff (most images recover on a second try) rather
        // than failing the card outright.
        let data: Data
        do {
            data = try await MuseumHTTP.data(for: req)
        } catch let failure as MuseumHTTP.Failure {
            throw ImageError.http(failure.message)
        }

        // gpt-image-2 returns base64 PNG (no URL form).
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.data.first?.b64_json,
              let imageData = Data(base64Encoded: b64) else {
            throw ImageError.empty
        }

        #if DEBUG
        Self.debugSaveRawImage(imageData)
        #endif

        return imageData
    }

    #if DEBUG
    /// DEBUG ONLY — writes the raw generated PNG to the Mac host `~/Downloads` (via the
    /// simulator's `SIMULATOR_HOST_HOME`) and logs its pixel dimensions, so we can confirm
    /// whether the GPT output is landscape or portrait independent of how it's mounted on the
    /// wall. No-op on device (the env var is absent there).
    private static func debugSaveRawImage(_ data: Data) {
        guard let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return }
        let (w, h) = pngPixelSize(data)
        let file = URL(fileURLWithPath: host)
            .appendingPathComponent("Downloads")
            .appendingPathComponent("ba396_raw_\(Int(Date().timeIntervalSince1970 * 1000)).png")
        try? data.write(to: file)
        print("🖼️ BA396 raw GPT image: \(w)x\(h)  (\(w >= h ? "LANDSCAPE" : "PORTRAIT"))  → \(file.path)")
    }

    /// Reads width/height straight from a PNG's IHDR chunk (bytes 16…23, big-endian) — no
    /// UIKit needed. Returns (0, 0) if the data isn't a recognisable PNG.
    private static func pngPixelSize(_ data: Data) -> (Int, Int) {
        guard data.count >= 24 else { return (0, 0) }
        func be32(_ offset: Int) -> Int {
            let b = [Int](data[data.startIndex + offset ..< data.startIndex + offset + 4].map(Int.init))
            return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
        }
        return (be32(16), be32(20))
    }
    #endif

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

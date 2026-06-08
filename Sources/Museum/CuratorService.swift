import Foundation

/// Stage A — "The Curator". Turns the visitor's answers into a 5-beat Hero's-Journey
/// `MuseumStory` via the OpenAI Responses API over plain `URLSession` (mirrors
/// `ConversationService`'s networking shape). Structured output is constrained with a
/// strict `text.format` json_schema, so the `output_text` content is guaranteed-valid JSON
/// that decodes straight into `MuseumStory`.
///
/// A value type (`struct`) so it is `Sendable` and can be captured by the gallery's
/// generation tasks without actor ceremony.
struct CuratorService {

    enum CuratorError: Error { case missingKey, http(String), empty, decode }

    /// Single switchable constant. `json_schema` structured outputs require a model in the
    /// gpt-4o-2024-08-06-or-later family. `gpt-4o-2024-08-06` is non-reasoning, so it returns
    /// the ~2k JSON in seconds rather than the tens of seconds a reasoning model spends — the
    /// story leg is on the user's critical path before they enter the museum, so speed wins
    /// here. Swap to `gpt-5.5` (the 2026 flagship) if you want the highest story quality and
    /// can absorb the extra latency. List what your key can use:
    ///   curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"
    private static let model = "gpt-4o-2024-08-06"

    func generate(_ answers: MuseumAnswers) async throws -> MuseumStory {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { throw CuratorError.missingKey }

        // Body built as a dictionary (not Codable structs) because the nested json_schema
        // is far cleaner to express inline than to model as types.
        let body: [String: Any] = [
            "model": Self.model,
            "instructions": MuseumPrompt.system,
            "input": [
                ["role": "user", "content": MuseumPrompt.fewShotUser],
                ["role": "assistant", "content": MuseumPrompt.fewShotAssistant],
                ["role": "user", "content": answers.promptInput],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "museum_story",
                    "strict": true,
                    "schema": MuseumPrompt.jsonSchema,
                ],
            ],
            // Headroom so a reasoning model's tokens plus the ~2k JSON don't truncate the output.
            "max_output_tokens": 8000,
        ]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Transient OpenAI/Cloudflare errors (520–524) and network blips self-heal via the
        // shared retry helper; only a permanent failure or exhausted retries reaches here,
        // already carrying a UI-safe message (never a raw HTML error page).
        let data: Data
        do {
            data = try await MuseumHTTP.data(for: req)
        } catch let failure as MuseumHTTP.Failure {
            throw CuratorError.http(failure.message)
        }

        // Responses API returns an `output` array; the JSON lives in the message item's
        // `output_text` content part(s). A reasoning item may precede it — filter by type.
        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: data)
        let text = envelope.output
            .compactMap(\.content)
            .flatMap { $0 }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty, let storyData = text.data(using: .utf8) else {
            throw CuratorError.empty
        }
        do {
            return try JSONDecoder().decode(MuseumStory.self, from: storyData)
        } catch {
            throw CuratorError.decode
        }
    }

    /// The OpenAI Responses API envelope (only the fields we read). `output` holds message
    /// (and possibly reasoning) items; the JSON we want is in `output_text` content parts.
    private struct ResponsesEnvelope: Decodable {
        struct Item: Decodable { let content: [Part]? }
        struct Part: Decodable { let type: String; let text: String? }
        let output: [Item]
    }

    /// Friendly one-liner for the gallery's error state.
    static func describe(_ error: Error) -> String {
        switch error {
        case CuratorError.missingKey:
            return "Add an OpenAI API key in Secrets.swift to build your museum."
        case CuratorError.decode:
            return "The Curator's reply couldn't be read. Try again."
        case CuratorError.http(let msg):
            return "The Curator couldn't answer just now.\n\(msg)"
        default:
            return "The Curator couldn't answer just now."
        }
    }
}

/// Shared networking for the Museum's two OpenAI calls (Curator + image painter). Lives
/// here (rather than its own file) because the Xcode project isn't a file-system-synchronized
/// group — a new file would need manual `project.pbxproj` surgery — and both callers are in
/// this same module.
///
/// Performs a request with bounded retries on *transient* failures: network blips and
/// 5xx / Cloudflare edge errors (520–524, the wall-of-HTML the user hit) self-heal with
/// exponential backoff instead of becoming a dead end. Permanent failures (4xx) throw at
/// once. The thrown message is always UI-safe — a raw HTML error page is never surfaced.
enum MuseumHTTP {

    /// A non-2xx response or exhausted retries. `message` is already cleaned for display.
    struct Failure: Error { let message: String }

    /// Sends `req` up to `maxAttempts` times. Returns the 2xx body, else throws `Failure`.
    static func data(for req: URLRequest, maxAttempts: Int = 3) async throws -> Data {
        var lastMessage = "The service didn't respond. Please try again."
        for attempt in 1...maxAttempts {
            if attempt > 1 {
                // Exponential backoff between tries: 1s, then 2s, …
                try? await Task.sleep(for: .seconds(1 << (attempt - 2)))
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else { return data }
                if (200...299).contains(http.statusCode) { return data }
                let message = friendly(status: http.statusCode, body: data)
                if isTransient(http.statusCode) { lastMessage = message; continue }
                throw Failure(message: message)           // permanent 4xx — stop now
            } catch let urlError as URLError {
                lastMessage = "Network problem — please check your connection and try again."
                _ = urlError
                continue                                  // network blip — retry
            }
        }
        throw Failure(message: lastMessage)
    }

    /// 408/429 and any 5xx (covers Cloudflare 520–524) are worth a retry.
    private static func isTransient(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }

    /// A UI-safe one-liner. Cloudflare's 5xx pages are full HTML — never show them raw; for
    /// those (and empty bodies) describe the status instead. JSON error bodies (the usual
    /// 4xx shape) are short and useful, so a trimmed snippet passes through.
    private static func friendly(status: Int, body: Data) -> String {
        let raw = (String(data: body, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let looksHTML = raw.first == "<" || lower.contains("<!doctype") || lower.contains("<html")
        if raw.isEmpty || looksHTML {
            return status >= 500
                ? "The service is busy right now (HTTP \(status)). Please try again in a moment."
                : "Request failed (HTTP \(status))."
        }
        return "HTTP \(status): \(raw.prefix(200))"
    }
}

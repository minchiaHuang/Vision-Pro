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
    /// gpt-4o-2024-08-06-or-later family. `gpt-5.5` is the 2026 flagship (best story
    /// quality); if your account doesn't have it, fall back to `gpt-4o-2024-08-06`.
    /// List what your key can use:
    ///   curl https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"
    private static let model = "gpt-5.5"

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

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw CuratorError.http("HTTP \(http.statusCode): \(snippet)")
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

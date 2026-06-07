import Foundation

/// Stage A — "The Curator". Turns the visitor's answers into a 5-beat Hero's-Journey
/// `MuseumStory` via OpenAI chat-completions over plain `URLSession` (mirrors
/// `ConversationService`'s networking shape). Structured output is constrained with a
/// strict `json_schema`, so `choices[0].message.content` is guaranteed-valid JSON that
/// decodes straight into `MuseumStory`.
///
/// A value type (`struct`) so it is `Sendable` and can be captured by the gallery's
/// generation tasks without actor ceremony.
struct CuratorService {

    enum CuratorError: Error { case missingKey, http(String), empty, decode }

    /// Single switchable constant.
    /// ⚠️ Set this to a CURRENT OpenAI text model that supports `json_schema` structured
    /// outputs (verify at the OpenAI models docs). The default below may be retired —
    /// change it when you add your key.
    private static let model = "gpt-4o"

    func generate(_ answers: MuseumAnswers) async throws -> MuseumStory {
        let key = Secrets.openAIAPIKey
        guard !key.isEmpty else { throw CuratorError.missingKey }

        // Body built as a dictionary (not Codable structs) because the nested json_schema
        // is far cleaner to express inline than to model as types.
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": MuseumPrompt.system],
                ["role": "user", "content": MuseumPrompt.fewShotUser],
                ["role": "assistant", "content": MuseumPrompt.fewShotAssistant],
                ["role": "user", "content": answers.promptInput],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "museum_story",
                    "strict": true,
                    "schema": MuseumPrompt.jsonSchema,
                ],
            ],
        ]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw CuratorError.http("HTTP \(http.statusCode): \(snippet)")
        }

        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = envelope.choices.first?.message.content,
              let storyData = content.data(using: .utf8) else {
            throw CuratorError.empty
        }
        do {
            return try JSONDecoder().decode(MuseumStory.self, from: storyData)
        } catch {
            throw CuratorError.decode
        }
    }

    /// The OpenAI chat-completions envelope (only the field we read).
    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String? }
        let choices: [Choice]
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

import Foundation
import Observation
import UIKit

/// Feasibility spike: World Labs Marble API client (text -> world -> panorama image).
/// Flow: POST worlds:generate -> poll operations/{id} until done -> download pano_url.
/// Generation takes ~5 minutes and consumes paid credits.
@MainActor
@Observable
final class WorldLabsService {

    enum Status: Equatable {
        case idle
        case generating(progress: Int)   // 0-100
        case downloading
        case ready(UIImage)
        case failed(String)
    }

    private(set) var status: Status = .idle

    private let apiKey = Secrets.worldLabsAPIKey
    private let base = "https://api.worldlabs.ai/marble/v1"
    private let model = "marble-1.0-draft"

    private let pollInterval: Duration = .seconds(6)
    private let maxPolls = 120   // ~12 minutes ceiling

    func run(prompt: String) async {
        guard !apiKey.isEmpty else {
            status = .failed("Missing World Labs API key (Secrets.swift).")
            return
        }
        status = .generating(progress: 0)
        do {
            let operationId = try await generate(prompt: prompt)
            let panoURL = try await pollUntilPano(operationId: operationId)
            status = .downloading
            let image = try await downloadImage(from: panoURL)
            status = .ready(image)
        } catch {
            status = .failed(message(for: error))
        }
    }

    // MARK: - Generate

    private func generate(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(base)/worlds:generate")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "WLT-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GenerateRequest(
            display_name: "Visiting Artisan spike",
            model: model,
            world_prompt: .init(type: "text", text_prompt: prompt),
            permission: .init(public: false)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ensureOK(response, data: data)
        let decoded = try JSONDecoder().decode(OperationResponse.self, from: data)
        guard let id = decoded.operation_id else {
            throw SpikeError.message("Generate response had no operation_id.")
        }
        return id
    }

    // MARK: - Poll

    private func pollUntilPano(operationId: String) async throws -> URL {
        for _ in 0..<maxPolls {
            try await Task.sleep(for: pollInterval)

            var request = URLRequest(url: URL(string: "\(base)/operations/\(operationId)")!)
            request.setValue(apiKey, forHTTPHeaderField: "WLT-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureOK(response, data: data)
            let op = try JSONDecoder().decode(OperationResponse.self, from: data)

            if let err = op.error, let msg = err.message ?? err.code {
                throw SpikeError.message("Generation failed: \(msg)")
            }

            if op.done == true {
                // Operation snapshot may have null pano_url for draft model.
                // Fall back to GET /worlds/{world_id} which reflects current asset state.
                if let pano = op.response?.assets?.imagery?.pano_url,
                   let url = URL(string: pano) {
                    return url
                }
                guard let worldId = op.metadata?.world_id else {
                    throw SpikeError.message("World finished but no pano_url and no world_id in metadata.")
                }
                return try await fetchPanoURL(worldId: worldId)
            }

            let pct = op.metadata?.progress?.status == "SUCCEEDED" ? 100
                : (op.metadata?.progress?.status == "IN_PROGRESS" ? 50 : 0)
            status = .generating(progress: pct)
        }
        throw SpikeError.message("Timed out waiting for world generation.")
    }

    // MARK: - Fetch pano from worlds endpoint

    /// GET /worlds/{worldId} returns top-level `assets` with current pano_url,
    /// which may be populated after the operation completes. Retries briefly.
    private func fetchPanoURL(worldId: String) async throws -> URL {
        for attempt in 1...5 {
            if attempt > 1 { try await Task.sleep(for: .seconds(5)) }
            var request = URLRequest(url: URL(string: "\(base)/worlds/\(worldId)")!)
            request.setValue(apiKey, forHTTPHeaderField: "WLT-Api-Key")
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureOK(response, data: data)
            let decoded = try JSONDecoder().decode(WorldGetResponse.self, from: data)
            if let pano = decoded.assets?.imagery?.pano_url,
               let url = URL(string: pano) {
                return url
            }
        }
        throw SpikeError.message("Panorama URL not available after retries.")
    }

    // MARK: - Download

    private func downloadImage(from url: URL) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        try ensureOK(response, data: data)
        guard let image = UIImage(data: data) else {
            throw SpikeError.message("Downloaded panorama could not be decoded as an image.")
        }
        return image
    }

    // MARK: - Helpers

    private func ensureOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let hint = http.statusCode == 402 || http.statusCode == 403
                ? " (check the account has API credits)"
                : ""
            throw SpikeError.message("HTTP \(http.statusCode)\(hint): \(bodyText.prefix(300))")
        }
    }

    private func message(for error: Error) -> String {
        if let spike = error as? SpikeError, case let .message(text) = spike { return text }
        return error.localizedDescription
    }

    private enum SpikeError: Error { case message(String) }
}

// MARK: - Wire format

private struct GenerateRequest: Encodable {
    struct WorldPrompt: Encodable { let type: String; let text_prompt: String }
    struct Permission: Encodable { let `public`: Bool }
    let display_name: String
    let model: String
    let world_prompt: WorldPrompt
    let permission: Permission
}

private struct OperationResponse: Decodable {
    let operation_id: String?
    let done: Bool?
    let error: ErrorInfo?
    let metadata: Metadata?
    let response: WorldObject?

    struct ErrorInfo: Decodable { let code: String?; let message: String? }
    struct Metadata: Decodable {
        let world_id: String?
        let progress: ProgressInfo?
        struct ProgressInfo: Decodable { let status: String? }
    }
}

private struct WorldGetResponse: Decodable {
    // Top-level "assets" from GET /worlds/{id} reflects current state.
    // NOT response.assets — that is a stale operation snapshot.
    let assets: WorldObject.Assets?
}

private struct WorldObject: Decodable {
    let assets: Assets?
    struct Assets: Decodable { let imagery: Imagery? }
    struct Imagery: Decodable { let pano_url: String? }
}

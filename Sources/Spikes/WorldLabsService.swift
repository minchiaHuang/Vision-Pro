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

    /// Set once generation completes: the world's id and the remote (public CDN)
    /// `.spz` URL for the walkable 3D splat. Downloaded on demand by the world phase.
    private(set) var worldId: String?
    private(set) var splatRemoteURL: URL?

    // Splat point-cloud density preference (keys in `spz_urls`): higher = sharper but
    // larger download, slower decode, and more memory. "full_res" can be millions of
    // points. We pick the first AVAILABLE key in this order — "500k" is the default
    // (quality/perf balance for a walkable 6DoF world); fall back to lighter/heavier
    // tiers if a world doesn't expose it. Switching resolution does NOT cost extra
    // credits (same world, different download). Applies to both iOS and visionOS.
    private let splatResolutionPreference = ["500k", "100k", "full_res"]
    private let apiKey = Secrets.worldLabsAPIKey
    private let base = "https://api.worldlabs.ai/marble/v1"
    // World-generation model. "marble-1.1" = current standard (better lighting,
    // contrast, fidelity than the old "marble-1.0-draft"; 1,500 credits/world).
    // "marble-1.1-plus" costs more but builds bigger worlds for outdoor/large
    // indoor prompts (= a larger walkable 6DoF bubble).
    private let model = "marble-1.1"

    private let pollInterval: Duration = .seconds(6)
    private let maxPolls = 120   // ~12 minutes ceiling

    /// The API reports only a status string (PENDING/IN_PROGRESS/SUCCEEDED) with no
    /// numeric percent, so the progress bar is *estimated* from elapsed time over this
    /// typical generation duration, and held below 100 until the operation is done.
    private let expectedDuration: Double = 300   // ~5 min, typical

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
        let start = Date()
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
                // GET /worlds/{id} is the reliable source for current assets (the
                // operation snapshot may carry a null pano_url for the draft model),
                // and it also yields the splat spz_urls in the same call.
                if let worldId = op.metadata?.world_id {
                    self.worldId = worldId
                    let assets = try await fetchAssets(worldId: worldId)
                    self.splatRemoteURL = assets.spz
                    if let pano = assets.pano { return pano }
                }
                if let pano = op.response?.assets?.imagery?.pano_url,
                   let url = URL(string: pano) {
                    return url
                }
                throw SpikeError.message("World finished but no pano_url available.")
            }

            // No numeric progress from the API — estimate from elapsed time so the
            // bar advances steadily, capped below 100 until the operation completes.
            let elapsed = Date().timeIntervalSince(start)
            let pct = min(95, Int(elapsed / expectedDuration * 100))
            status = .generating(progress: pct)
        }
        throw SpikeError.message("Timed out waiting for world generation.")
    }

    // MARK: - Fetch assets from worlds endpoint

    /// GET /worlds/{worldId} returns top-level `assets` with the current pano_url
    /// and splat spz_urls, which may populate shortly after the operation completes.
    /// Retries briefly until the panorama is present; returns the splat URL if ready.
    private func fetchAssets(worldId: String) async throws -> (pano: URL?, spz: URL?) {
        for attempt in 1...5 {
            if attempt > 1 { try await Task.sleep(for: .seconds(5)) }
            var request = URLRequest(url: URL(string: "\(base)/worlds/\(worldId)")!)
            request.setValue(apiKey, forHTTPHeaderField: "WLT-Api-Key")
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureOK(response, data: data)
            let decoded = try JSONDecoder().decode(WorldGetResponse.self, from: data)
            let pano = decoded.assets?.imagery?.pano_url.flatMap { URL(string: $0) }
            let spz = resolveSplatURL(from: decoded.assets?.splats?.spz_urls)
            if pano != nil { return (pano, spz) }
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

    /// Picks the splat `.spz` URL using `splatResolutionPreference` order, returning the
    /// first tier the world actually exposes. Falls back across tiers so a missing
    /// preferred key (e.g. no "500k") still yields a usable splat instead of nil.
    func resolveSplatURL(from spzURLs: [String: String]?) -> URL? {
        guard let spzURLs else { return nil }
        for key in splatResolutionPreference {
            if let raw = spzURLs[key], let url = URL(string: raw) { return url }
        }
        // Preference list didn't match any exposed key — take whatever is present.
        return spzURLs.values.compactMap { URL(string: $0) }.first
    }

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

struct OperationResponse: Decodable {
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

struct WorldGetResponse: Decodable {
    // Top-level "assets" from GET /worlds/{id} reflects current state.
    // NOT response.assets — that is a stale operation snapshot.
    let assets: WorldObject.Assets?
}

struct WorldObject: Decodable {
    let assets: Assets?
    struct Assets: Decodable { let imagery: Imagery?; let splats: Splats? }
    struct Imagery: Decodable { let pano_url: String? }
    // 3D Gaussian splat. spz_urls keys: "100k" / "500k" / "full_res" (public CDN).
    struct Splats: Decodable { let spz_urls: [String: String]? }
}

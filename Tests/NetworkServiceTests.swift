import Testing
import Foundation
import UIKit
@testable import VisitingArtisan

/// Offline tests for the two network clients, driven by `StubURLProtocol` over an
/// injected `URLSession`. Serialized because the stub's route is process-global.
@MainActor
@Suite(.serialized)
struct NetworkServiceTests {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    private func onePixelPNG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func worldLabs(apiKey: String = "test") -> WorldLabsService {
        WorldLabsService(apiKey: apiKey, session: StubURLProtocol.session(),
                         pollInterval: .zero, maxPolls: 3, retryDelay: .zero)
    }

    // MARK: - WorldLabsService orchestration

    @Test func happyPathReachesReadyWithWorldIdAndSplat() async {
        StubURLProtocol.route = { url in
            let s = url.absoluteString
            if s.contains("worlds:generate") { return (200, self.json(#"{"operation_id":"op_1"}"#)) }
            if s.contains("/operations/")    { return (200, self.json(#"{"done":true,"metadata":{"world_id":"w_1"}}"#)) }
            if s.contains("/worlds/w_1")     { return (200, self.json(#"{"assets":{"imagery":{"pano_url":"https://cdn.example/p.png"},"splats":{"spz_urls":{"500k":"https://cdn.example/x_500k.spz"}}}}"#)) }
            if s.contains("p.png")           { return (200, self.onePixelPNG()) }
            return (404, Data())
        }
        let svc = worldLabs()
        await svc.run(prompt: "a calm meadow")

        #expect(svc.worldId == "w_1")
        #expect(svc.splatRemoteURL?.absoluteString == "https://cdn.example/x_500k.spz")
        if case .ready = svc.status {} else { Issue.record("expected .ready, got \(svc.status)") }
    }

    @Test func missingKeyFailsBeforeAnyNetwork() async {
        let svc = worldLabs(apiKey: "")
        await svc.run(prompt: "x")
        if case let .failed(msg) = svc.status { #expect(msg.contains("Missing")) }
        else { Issue.record("expected .failed") }
    }

    @Test func generate402FailsWithCreditsHint() async {
        StubURLProtocol.route = { _ in (402, Data("no credits".utf8)) }
        let svc = worldLabs()
        await svc.run(prompt: "x")
        if case let .failed(msg) = svc.status {
            #expect(msg.contains("402"))
            #expect(msg.contains("credits"))
        } else { Issue.record("expected .failed") }
    }

    @Test func operationErrorObjectFails() async {
        StubURLProtocol.route = { url in
            let s = url.absoluteString
            if s.contains("worlds:generate") { return (200, self.json(#"{"operation_id":"op_1"}"#)) }
            if s.contains("/operations/")    { return (200, self.json(#"{"error":{"code":"BAD","message":"generation blew up"}}"#)) }
            return (404, Data())
        }
        let svc = worldLabs()
        await svc.run(prompt: "x")
        if case let .failed(msg) = svc.status { #expect(msg.contains("generation blew up")) }
        else { Issue.record("expected .failed") }
    }

    @Test func neverDoneTimesOut() async {
        StubURLProtocol.route = { url in
            let s = url.absoluteString
            if s.contains("worlds:generate") { return (200, self.json(#"{"operation_id":"op_1"}"#)) }
            if s.contains("/operations/")    { return (200, self.json(#"{"done":false}"#)) }
            return (404, Data())
        }
        let svc = WorldLabsService(apiKey: "test", session: StubURLProtocol.session(),
                                   pollInterval: .zero, maxPolls: 2, retryDelay: .zero)
        await svc.run(prompt: "x")
        if case let .failed(msg) = svc.status { #expect(msg.contains("Timed out")) }
        else { Issue.record("expected .failed") }
    }

    @Test func finishedWithoutPanoFails() async {
        StubURLProtocol.route = { url in
            let s = url.absoluteString
            if s.contains("worlds:generate") { return (200, self.json(#"{"operation_id":"op_1"}"#)) }
            if s.contains("/operations/")    { return (200, self.json(#"{"done":true}"#)) }   // no world_id, no assets
            return (404, Data())
        }
        let svc = worldLabs()
        await svc.run(prompt: "x")
        if case let .failed(msg) = svc.status { #expect(msg.contains("no pano_url")) }
        else { Issue.record("expected .failed") }
    }

    // MARK: - AnthropicClient (Claude Messages API)

    @Test func anthropicHappyPathJoinsTextBlocks() async throws {
        StubURLProtocol.route = { _ in
            (200, self.json(#"{"content":[{"type":"text","text":"Hello"},{"type":"text","text":"there"}]}"#))
        }
        let client = AnthropicClient(apiKey: "test", session: StubURLProtocol.session())
        let reply = try await client.reply(system: "sys", history: [.init(role: "user", content: "hi")])
        #expect(reply == "Hello there")
    }

    @Test func anthropicMissingKeyThrows() async {
        let client = AnthropicClient(apiKey: "", session: StubURLProtocol.session())
        await #expect(throws: ConversationService.ConvError.self) {
            _ = try await client.reply(system: "s", history: [])
        }
    }

    @Test func anthropicHTTPErrorThrows() async {
        StubURLProtocol.route = { _ in (500, Data("boom".utf8)) }
        let client = AnthropicClient(apiKey: "test", session: StubURLProtocol.session())
        await #expect(throws: ConversationService.ConvError.self) {
            _ = try await client.reply(system: "s", history: [])
        }
    }

    @Test func anthropicEmptyContentThrows() async {
        StubURLProtocol.route = { _ in (200, self.json(#"{"content":[]}"#)) }
        let client = AnthropicClient(apiKey: "test", session: StubURLProtocol.session())
        await #expect(throws: ConversationService.ConvError.self) {
            _ = try await client.reply(system: "s", history: [])
        }
    }
}

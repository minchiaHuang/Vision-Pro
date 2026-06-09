import Testing
import Foundation
import UIKit
@testable import VisitingArtisan

/// Offline tests for `OpenAIImageService` — the BA396 gallery wall-photo generator.
///
/// The Hero's-Journey prompt template and the disk writer are pure and tested directly;
/// the network path is driven by an injected `URLSession` plus an injected key.
///
/// This suite uses its OWN `OAIStubURLProtocol` (not the shared `StubURLProtocol`) on
/// purpose: Swift Testing runs suites in parallel, and the stub's `route` is a process
/// global. `@Suite(.serialized)` only serializes tests WITHIN a suite, so sharing one
/// global route with `NetworkServiceTests` lets the two suites stomp each other's routes
/// mid-run. A dedicated stub gives this suite an isolated route and keeps both suites green.
@MainActor
@Suite(.serialized)
struct OpenAIImageServiceTests {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    private func onePixelPNG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    // MARK: - heroJourneyPrompts (pure)

    @Test func promptsHaveFiveBeatsInHeroJourneyOrder() {
        let p = OpenAIImageService.heroJourneyPrompts(goal: "a concert pianist")
        #expect(p.count == 5)
        #expect(p[0].contains("Ordinary world"))
        #expect(p[1].contains("The call"))
        #expect(p[2].contains("Trials"))
        #expect(p[3].contains("Transformation"))
        #expect(p[4].contains("Mastery"))
    }

    @Test func promptsInterpolateAndTrimGoal() {
        let p = OpenAIImageService.heroJourneyPrompts(goal: "  swimming \n")
        #expect(p.allSatisfy { $0.contains("swimming") })
        // The goal is trimmed before interpolation, so no surrounding whitespace leaks through.
        #expect(p.allSatisfy { !$0.contains("swimming \n") })
        #expect(p.allSatisfy { !$0.contains("  swimming") })
    }

    @Test func everyPromptCarriesStyleGuard() {
        let p = OpenAIImageService.heroJourneyPrompts(goal: "x")
        #expect(p.allSatisfy { $0.contains("No text") })
        #expect(p.allSatisfy { $0.contains("photorealistic") })
    }

    @Test func promptsAreDeterministic() {
        #expect(OpenAIImageService.heroJourneyPrompts(goal: "chef")
                == OpenAIImageService.heroJourneyPrompts(goal: "chef"))
    }

    // MARK: - saveToDisk

    @Test func saveEmptyReturnsNil() {
        #expect(OpenAIImageService.saveToDisk([]) == nil)
    }

    @Test func saveWritesPNGAndReturnsDirectory() throws {
        let img = try #require(UIImage(data: onePixelPNG()))
        let dir = try #require(OpenAIImageService.saveToDisk([img]))
        let file = dir.appendingPathComponent("scene_01.png")
        #expect(FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - generateImage network path (injected session + key)

    @Test func emptyKeyThrowsMissingKeyBeforeAnyNetwork() async {
        do {
            _ = try await OpenAIImageService.generateImage(
                prompt: "x", apiKey: "", session: OAIStubURLProtocol.session())
            Issue.record("expected a throw")
        } catch OpenAIImageService.ImageError.missingKey {
            // expected
        } catch {
            Issue.record("expected .missingKey, got \(error)")
        }
    }

    @Test func httpErrorThrowsApiWithStatus() async {
        OAIStubURLProtocol.route = { _ in (402, Data("no credits".utf8)) }
        do {
            _ = try await OpenAIImageService.generateImage(
                prompt: "x", apiKey: "test", session: OAIStubURLProtocol.session())
            Issue.record("expected a throw")
        } catch let OpenAIImageService.ImageError.api(status, _) {
            #expect(status == 402)
        } catch {
            Issue.record("expected .api, got \(error)")
        }
    }

    @Test func emptyDataArrayThrowsDecode() async {
        OAIStubURLProtocol.route = { _ in (200, self.json(#"{"data":[]}"#)) }
        do {
            _ = try await OpenAIImageService.generateImage(
                prompt: "x", apiKey: "test", session: OAIStubURLProtocol.session())
            Issue.record("expected a throw")
        } catch OpenAIImageService.ImageError.decode {
            // expected: 200 but no usable image payload
        } catch {
            Issue.record("expected .decode, got \(error)")
        }
    }

    @Test func happyPathDecodesImageFromBase64() async throws {
        let b64 = onePixelPNG().base64EncodedString()
        OAIStubURLProtocol.route = { _ in (200, self.json(#"{"data":[{"b64_json":"\#(b64)"}]}"#)) }
        let image = try await OpenAIImageService.generateImage(
            prompt: "x", apiKey: "test", session: OAIStubURLProtocol.session())
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}

/// Dedicated stub for `OpenAIImageServiceTests` — see the suite doc comment for why this
/// is separate from the shared `StubURLProtocol`. Same scripted-response design; `route`
/// is read on the URL-loading thread and set by the (serialized) suite before each request.
private final class OAIStubURLProtocol: URLProtocol {

    static var route: ((URL) -> (status: Int, body: Data))?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAIStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (status, body) = Self.route?(url) ?? (500, Data())
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

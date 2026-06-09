import Testing
import Foundation
@testable import VisitingArtisan

/// HTTP / error-string mapping for the two service clients. Pure logic — no
/// network: we hand `ensureOK` a synthetic `HTTPURLResponse` and check the
/// thrown message, and call `describe` on known error cases.
@MainActor
struct ErrorMappingTests {

    private func response(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.example/x")!,
                        statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    private func capture(_ body: () throws -> Void) -> String? {
        do { try body(); return nil }
        catch { return String(describing: error) }
    }

    // MARK: - WorldLabsService.ensureOK

    @Test func successStatusDoesNotThrow() throws {
        let service = WorldLabsService()
        try service.ensureOK(response(200), data: Data())   // throwing → test fails if it throws
    }

    @Test func paymentRequiredHintsAtCredits() {
        let service = WorldLabsService()
        let msg = capture { try service.ensureOK(response(402), data: Data("nope".utf8)) }
        #expect(msg?.contains("402") == true)
        #expect(msg?.contains("credits") == true)
    }

    @Test func forbiddenAlsoHintsAtCredits() {
        let service = WorldLabsService()
        let msg = capture { try service.ensureOK(response(403), data: Data()) }
        #expect(msg?.contains("403") == true)
        #expect(msg?.contains("credits") == true)
    }

    @Test func serverErrorReportsCodeWithoutCreditHint() {
        let service = WorldLabsService()
        let msg = capture { try service.ensureOK(response(500), data: Data("boom".utf8)) }
        #expect(msg?.contains("500") == true)
        #expect(msg?.contains("credits") == false)
    }

    // MARK: - ConversationService.describe

    @Test func missingKeyDescribesHowToAddAKey() {
        let msg = ConversationService.describe(ConversationService.ConvError.missingKey)
        #expect(msg == "Add an Anthropic API key in Secrets.swift to talk with your guide.")
    }

    @Test func otherErrorsGetTheGenericGuideMessage() {
        #expect(ConversationService.describe(ConversationService.ConvError.empty)
                == "The guide couldn't answer just now.")
        #expect(ConversationService.describe(ConversationService.ConvError.http("HTTP 500"))
                == "The guide couldn't answer just now.")
    }
}

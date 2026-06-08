import Testing
import Foundation
@testable import VisitingArtisan

/// Contract tests for the World Labs JSON wire format. They guard our decoding
/// assumptions against de-identified sample payloads, so an API field rename
/// surfaces here rather than as a silent nil in the generation flow.
struct WorldLabsWireFormatTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decodesAFinishedOperation() throws {
        let json = """
        { "operation_id": "op_123", "done": true, "metadata": { "world_id": "w_456" } }
        """
        let op = try decode(OperationResponse.self, json)
        #expect(op.operation_id == "op_123")
        #expect(op.done == true)
        #expect(op.metadata?.world_id == "w_456")
        #expect(op.error == nil)
    }

    @Test func decodesAnInProgressOperationWithStatus() throws {
        let json = """
        { "operation_id": "op_1", "done": false, "metadata": { "progress": { "status": "IN_PROGRESS" } } }
        """
        let op = try decode(OperationResponse.self, json)
        #expect(op.done == false)
        #expect(op.metadata?.progress?.status == "IN_PROGRESS")
        #expect(op.metadata?.world_id == nil)
    }

    @Test func decodesAnErrorOperation() throws {
        let json = """
        { "done": true, "error": { "code": "QUOTA", "message": "out of credits" } }
        """
        let op = try decode(OperationResponse.self, json)
        #expect(op.error?.code == "QUOTA")
        #expect(op.error?.message == "out of credits")
    }

    @Test func decodesWorldAssetsWithPanoAndSplatTiers() throws {
        let json = """
        {
          "assets": {
            "imagery": { "pano_url": "https://cdn.example/pano.jpg" },
            "splats": { "spz_urls": { "100k": "https://cdn.example/x_100k.spz",
                                       "500k": "https://cdn.example/x_500k.spz" } }
          }
        }
        """
        let world = try decode(WorldGetResponse.self, json)
        #expect(world.assets?.imagery?.pano_url == "https://cdn.example/pano.jpg")
        #expect(world.assets?.splats?.spz_urls?["500k"] == "https://cdn.example/x_500k.spz")
        #expect(world.assets?.splats?.spz_urls?.count == 2)
    }

    @Test func toleratesMissingOptionalAssets() throws {
        let world = try decode(WorldGetResponse.self, "{}")
        #expect(world.assets == nil)
    }
}

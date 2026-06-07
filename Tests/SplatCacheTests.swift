#if os(visionOS)
import Testing
import Foundation
import simd
import MetalSplatter
import SplatIO
@testable import VisitingArtisan

/// `SplatCache` is the on-disk cache for decoded splat scenes. Tests cover the pure
/// `cachePath` key derivation and the binary `serialize`↔`deserialize` round-trip
/// (no disk, no Metal buffers).
struct SplatCacheTests {

    @Test func cachePathEncodesNameVersionAndFlipFlag() {
        let url = URL(fileURLWithPath: "/tmp/MyWorld.spz")
        let normal = SplatCache.cachePath(for: url, flipUpsideDown: false)
        let flipped = SplatCache.cachePath(for: url, flipUpsideDown: true)

        #expect(normal.lastPathComponent.hasPrefix("MyWorld-v"))
        #expect(normal.lastPathComponent.hasSuffix("-n.splatchache"))
        #expect(flipped.lastPathComponent.hasSuffix("-f.splatchache"))
        #expect(normal != flipped)   // flip flag forces a distinct cache file
    }

    @Test func serializeDeserializeRoundTrips() throws {
        let sh0 = try #require(SHDegree(rawValue: 0))
        let scene = SplatCache.CachedScene(
            calibration: matrix_identity_float4x4,
            locomotionPosition: SIMD3<Float>(1, 2, 3),
            locomotionSpan: 4.5,
            modelPlacement: matrix_identity_float4x4,
            pointCount: 7,
            shDegree: sh0,
            splatData: Data([1, 2, 3, 4]),
            shData: Data())

        let bytes = SplatCache.serialize(scene)
        let back = try SplatCache.deserialize(bytes)

        #expect(back.pointCount == 7)
        #expect(back.locomotionSpan == 4.5)
        #expect(back.locomotionPosition == SIMD3<Float>(1, 2, 3))
        #expect(back.splatData == Data([1, 2, 3, 4]))
        #expect(back.shData.isEmpty)
    }

    @Test func deserializeRejectsBadMagic() {
        #expect(throws: (any Error).self) {
            _ = try SplatCache.deserialize(Data([0, 1, 2, 3, 4, 5, 6, 7, 8]))
        }
    }
}
#endif

import Testing
import Foundation
import simd
@testable import VisitingArtisan

/// `ParametricWorldBuilder.ba396VisitOrder` turns the 6 BA396 portrait centroids into a clockwise
/// walking sequence; `ba396SpawnPose` places the user at the entrance — midway between the first
/// and last walls, pushed toward the hall centre, facing the first wall. Both pure math.
struct BA396VisitOrderTests {

    // Four anchors on the XZ axes: +X, +Z, -X, -Z (atan2(z,x) = 0, π/2, π, -π/2).
    private let axisCentroids: [SIMD3<Float>] = [
        SIMD3( 1, 0,  0),   // 0
        SIMD3( 0, 0,  1),   // 1
        SIMD3(-1, 0,  0),   // 2
        SIMD3( 0, 0, -1),   // 3
    ]

    // MARK: visit order

    /// A valid override permutation is returned verbatim (the on-device pin).
    @Test func validOverrideWins() {
        let order = ParametricWorldBuilder.ba396VisitOrder(centroids: axisCentroids,
                                                           manualOrder: [3, 2, 1, 0])
        #expect(order == [3, 2, 1, 0])
    }

    /// A malformed override (wrong length / not a permutation) is ignored, and the geometry order
    /// is still a full permutation of the tile indices.
    @Test func malformedOverrideIgnored() {
        let bad = ParametricWorldBuilder.ba396VisitOrder(centroids: axisCentroids, manualOrder: [0, 0])
        #expect(bad.count == 4)
        #expect(Set(bad) == Set(0..<4))
    }

    /// Counter-clockwise = atan2 ascending: -Z, +X, +Z, -X → [3, 0, 1, 2].
    @Test func counterClockwiseFollowsAscendingAngle() {
        let order = ParametricWorldBuilder.ba396VisitOrder(centroids: axisCentroids,
                                                           start: 0, clockwise: false, manualOrder: nil)
        #expect(order == [3, 0, 1, 2])
    }

    /// Clockwise reverses the ring → [2, 1, 0, 3].
    @Test func clockwiseReversesTheRing() {
        let order = ParametricWorldBuilder.ba396VisitOrder(centroids: axisCentroids,
                                                           start: 0, clockwise: true, manualOrder: nil)
        #expect(order == [2, 1, 0, 3])
    }

    /// `start` rotates the ring to begin at that ring index: ring [3,0,1,2] with start 1 → [0,1,2,3].
    @Test func startRotatesTheRing() {
        let order = ParametricWorldBuilder.ba396VisitOrder(centroids: axisCentroids,
                                                           start: 1, clockwise: false, manualOrder: nil)
        #expect(order == [0, 1, 2, 3])
    }

    /// Whatever the knobs, the result is always a complete permutation (no dropped/duplicated wall).
    @Test func resultIsAlwaysAPermutation() {
        for start in 0..<6 {
            for cw in [true, false] {
                let order = ParametricWorldBuilder.ba396VisitOrder(
                    centroids: (0..<6).map { i in
                        let a = Float(i) * .pi / 3
                        return SIMD3(cos(a), 0, sin(a))
                    },
                    start: start, clockwise: cw, manualOrder: nil)
                #expect(order.count == 6)
                #expect(Set(order) == Set(0..<6))
            }
        }
    }

    @Test func emptyCentroidsGiveEmptyOrder() {
        #expect(ParametricWorldBuilder.ba396VisitOrder(centroids: []).isEmpty)
    }

    // MARK: spawn pose

    /// Spawn stands midway between the first (`order[0]`) and last walls, pushed `standoff` toward
    /// the hall centre (origin) at `height`, facing the first wall.
    @Test func spawnPoseStandsBetweenFirstAndLastFacingFirst() {
        let anchors: [(centroid: SIMD3<Float>, normal: SIMD3<Float>)] = [
            (SIMD3(0, 2, -2), SIMD3(0, 0, 1)),   // wall 0 (image 1) — the one we face
            (SIMD3(2, 2,  0), SIMD3(-1, 0, 0)),  // wall 1 (last) — other side of the entrance
        ]
        let pose = ParametricWorldBuilder.ba396SpawnPose(anchors: anchors, order: [0, 1],
                                                         standoff: Float(2).squareRoot(), height: 0.5)
        let p = try! #require(pose)
        // mid (1,_,-1) + inward normalize((-1,0,1)) * √2 = (0,_,0); y overridden to 0.5.
        #expect(abs(p.position.x - 0)   < 1e-4)
        #expect(abs(p.position.y - 0.5) < 1e-4)
        #expect(abs(p.position.z - 0)   < 1e-4)
        // Faces image 1 at (0,_,-2) from (0,_,0): forward -Z → yaw 0.
        #expect(abs(p.yaw) < 1e-4)
    }

    /// When the first and last walls are symmetric about the origin, the entrance midpoint is the
    /// origin (degenerate inward → no push); spawn sits there and turns to face the first wall.
    @Test func spawnPoseFacesFirstWhenMidpointIsOrigin() {
        let anchors: [(centroid: SIMD3<Float>, normal: SIMD3<Float>)] = [
            (SIMD3(-3, 0, 0), SIMD3(1, 0, 0)),   // wall 0 (image 1), on the −X side
            (SIMD3( 3, 0, 0), SIMD3(-1, 0, 0)),  // wall 1 (last), on the +X side
        ]
        let pose = ParametricWorldBuilder.ba396SpawnPose(anchors: anchors, order: [0, 1],
                                                         standoff: 2, height: 0)
        let p = try! #require(pose)
        #expect(abs(p.position.x) < 1e-4)
        #expect(abs(p.position.z) < 1e-4)
        // Faces image 1 toward −X from the origin: forward −X → yaw = atan2(3, 0) = π/2.
        #expect(abs(p.yaw - .pi / 2) < 1e-4)
    }

    @Test func spawnPoseNilWhenOrderOrAnchorsEmpty() {
        #expect(ParametricWorldBuilder.ba396SpawnPose(anchors: [], order: [0]) == nil)
        let anchors: [(centroid: SIMD3<Float>, normal: SIMD3<Float>)] = [(.zero, SIMD3(0, 0, 1))]
        #expect(ParametricWorldBuilder.ba396SpawnPose(anchors: anchors, order: []) == nil)
    }
}

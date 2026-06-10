import Testing
import Foundation
import simd
@testable import VisitingArtisan

/// `ParametricWorldBuilder.ba396VisitOrder` turns the 6 BA396 portrait centroids into a clockwise
/// walking sequence; `ba396SpawnPose` centres the user in front of the (flat) portrait wall, pushed
/// back by the frame spread, facing the wall. Both pure math.
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

    /// Spawn centres in front of all the (flat-wall) frames, pushed back `standoffFactor` × the
    /// horizontal spread, facing the wall.
    @Test func spawnPoseCentresInFrontOfWall() {
        // Four frames on a flat z = -2 wall, symmetric about (0,0,-2); roomward normal +Z.
        let anchors: [(centroid: SIMD3<Float>, normal: SIMD3<Float>)] = [
            (SIMD3(-1,  1, -2), SIMD3(0, 0, 1)),
            (SIMD3( 1,  1, -2), SIMD3(0, 0, 1)),
            (SIMD3(-1, -1, -2), SIMD3(0, 0, 1)),
            (SIMD3( 1, -1, -2), SIMD3(0, 0, 1)),
        ]
        let pose = ParametricWorldBuilder.ba396SpawnPose(anchors: anchors,
                                                         standoffFactor: 2, height: 0, override: nil)
        let p = try! #require(pose)
        // centre (0,0,-2); horizontal spread 1; +Z normal × (1×2) → (0,0,0).
        #expect(abs(p.position.x) < 1e-4)
        #expect(abs(p.position.z) < 1e-4)
        // Faces the wall centre at -Z: forward -Z → yaw 0.
        #expect(abs(p.yaw) < 1e-4)
    }

    /// Faces the wall along its roomward normal regardless of orientation (here a +X wall).
    @Test func spawnPoseFacesWallAlongNormal() {
        // Two frames on a flat x = 2 wall; roomward normal -X (toward the room at x < 2).
        let anchors: [(centroid: SIMD3<Float>, normal: SIMD3<Float>)] = [
            (SIMD3(2,  1, -1), SIMD3(-1, 0, 0)),
            (SIMD3(2, -1,  1), SIMD3(-1, 0, 0)),
        ]
        let pose = ParametricWorldBuilder.ba396SpawnPose(anchors: anchors,
                                                         standoffFactor: 3, height: 0, override: nil)
        let p = try! #require(pose)
        // centre (2,0,0); spread 1; -X normal × 3 → (-1,0,0).
        #expect(abs(p.position.x - (-1)) < 1e-4)
        #expect(abs(p.position.z) < 1e-4)
        // Faces +X toward the wall: forward +X → yaw = -π/2.
        #expect(abs(p.yaw - (-.pi / 2)) < 1e-4)
    }

    @Test func spawnPoseNilWhenNoAnchors() {
        #expect(ParametricWorldBuilder.ba396SpawnPose(anchors: [], override: nil) == nil)
    }
}

#if os(visionOS)
import Testing
@testable import VisitingArtisan

/// `SplatModelManipulation` accumulates two-hand gesture deltas and lets the render
/// thread consume them atomically. Pure accumulator (no ARKit). Serialized because the
/// tests share the `.shared` singleton.
@Suite(.serialized)
struct SplatModelManipulationTests {

    @Test func addAccumulatesYawAdditivelyAndScaleMultiplicatively() {
        let m = SplatModelManipulation.shared
        m.reset()
        m.add(yaw: 0.1, scaleMul: 2)
        m.add(yaw: 0.2, scaleMul: 3)
        let delta = m.consume()
        #expect(delta != nil)
        #expect(abs((delta?.yaw ?? 0) - 0.3) < 1e-6)       // 0.1 + 0.2
        #expect(abs((delta?.scaleMul ?? 0) - 6) < 1e-6)    // 2 * 3
    }

    @Test func consumeReturnsNilWhenNothingAccumulated() {
        let m = SplatModelManipulation.shared
        m.reset()
        #expect(m.consume() == nil)
    }

    @Test func consumeResetsToIdentity() {
        let m = SplatModelManipulation.shared
        m.reset()
        m.add(yaw: 1, scaleMul: 5)
        _ = m.consume()
        #expect(m.consume() == nil)   // identity (no dirty) after a consume
    }

    @Test func resetDropsPendingDelta() {
        let m = SplatModelManipulation.shared
        m.add(yaw: 9, scaleMul: 9)
        m.reset()
        #expect(m.consume() == nil)
    }
}
#endif

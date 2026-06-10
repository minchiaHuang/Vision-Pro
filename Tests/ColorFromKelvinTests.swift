import Testing
import UIKit
@testable import VisitingArtisan

/// `ParametricWorldBuilder.colorFromKelvin` is a 3-keyframe Kelvin→colour curve
/// (3500 K amber, 5500 K neutral white, 7000 K cool). Pure math.
struct ColorFromKelvinTests {

    private func rgb(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private let tol: CGFloat = 1e-3

    @Test func warmEndpointAt3500K() {
        let c = rgb(ParametricWorldBuilder.colorFromKelvin(3500))
        #expect(abs(c.r - 1.0) < tol)
        #expect(abs(c.g - 0.76) < tol)
        #expect(abs(c.b - 0.44) < tol)
    }

    @Test func neutralWhiteAt5500K() {
        let c = rgb(ParametricWorldBuilder.colorFromKelvin(5500))
        #expect(abs(c.r - 1.0) < tol)
        #expect(abs(c.g - 1.0) < tol)
        #expect(abs(c.b - 1.0) < tol)
    }

    @Test func coolEndpointAt7000K() {
        let c = rgb(ParametricWorldBuilder.colorFromKelvin(7000))
        #expect(abs(c.r - 0.85) < tol)
        #expect(abs(c.g - 0.93) < tol)
        #expect(abs(c.b - 1.0) < tol)
    }

    /// The two linear segments must meet at 5500 K (no discontinuity in the curve).
    @Test func curveIsContinuousAcrossTheMidpoint() {
        let below = rgb(ParametricWorldBuilder.colorFromKelvin(5499))
        let above = rgb(ParametricWorldBuilder.colorFromKelvin(5501))
        #expect(abs(below.r - above.r) < 5e-3)
        #expect(abs(below.g - above.g) < 5e-3)
        #expect(abs(below.b - above.b) < 5e-3)
    }
}

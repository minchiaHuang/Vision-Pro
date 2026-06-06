import Testing
import UIKit
@testable import VisitingArtisan

/// `ParametricWorldBuilder.greyed` lerps a colour toward its Rec. 709 luminance
/// grey by `amount` (0…1), preserving alpha. Pure colour math (axis-4 saturation).
struct DesaturationTests {

    private func rgba(_ c: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
    private let tol: CGFloat = 1e-3

    @Test func amountZeroLeavesTheColourUnchanged() {
        let c = rgba(ParametricWorldBuilder.greyed(.red, amount: 0))
        #expect(abs(c.r - 1.0) < tol)
        #expect(abs(c.g - 0.0) < tol)
        #expect(abs(c.b - 0.0) < tol)
    }

    @Test func amountOneCollapsesToRec709Luminance() {
        // Pure red → luminance 0.2126, equal across channels.
        let red = rgba(ParametricWorldBuilder.greyed(.red, amount: 1))
        #expect(abs(red.r - 0.2126) < tol)
        #expect(abs(red.g - 0.2126) < tol)
        #expect(abs(red.b - 0.2126) < tol)

        // Pure green → 0.7152.
        let green = rgba(ParametricWorldBuilder.greyed(.green, amount: 1))
        #expect(abs(green.r - 0.7152) < tol)
        #expect(abs(green.g - 0.7152) < tol)
        #expect(abs(green.b - 0.7152) < tol)
    }

    @Test func alphaIsPreservedThroughDesaturation() {
        let translucentBlue = UIColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let out = rgba(ParametricWorldBuilder.greyed(translucentBlue, amount: 1))
        #expect(abs(out.r - 0.0722) < tol)   // blue luminance
        #expect(abs(out.g - 0.0722) < tol)
        #expect(abs(out.b - 0.0722) < tol)
        #expect(abs(out.a - 0.5) < tol)      // alpha untouched
    }

    @Test func partialAmountLandsBetweenColourAndGrey() {
        // Halfway: red channel between 1.0 (orig) and 0.2126 (grey) → ~0.606.
        let half = rgba(ParametricWorldBuilder.greyed(.red, amount: 0.5))
        #expect(half.r > 0.2126 && half.r < 1.0)
        #expect(abs(half.r - (1.0 + (0.2126 - 1.0) * 0.5)) < tol)
    }
}

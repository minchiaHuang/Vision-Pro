import Testing
import RealityKit
import UIKit
@testable import VisitingArtisan

/// RealityKit integration tests for the parametric world assembly. Runs on the Vision
/// Pro simulator (Metal-backed). Uses a synthetic box model so it needs no bundled USDZ.
@MainActor
struct ParametricWorldBuilderRealityTests {

    private func syntheticModel() -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: 2), materials: [SimpleMaterial()])
    }

    private func params(socialDensity: Int = 4, lightIntensity: Float = 1000,
                        colorTemperature: Float = 5500, saturation: Double = 1.0) -> WorldParams {
        WorldParams(archetype: .openNature, lightIntensity: lightIntensity,
                    colorTemperature: colorTemperature, saturation: saturation,
                    socialDensity: socialDensity, openness: 0.5,
                    biophilicDensity: 0.5, focal: .ownPath)
    }

    private func components(_ color: UIColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        guard let color else { return (-1, -1, -1) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    // MARK: - assemble

    @Test func assembleParentsModelThreeLightsAndOrbs() {
        let build = ParametricWorldBuilder.assemble(model: syntheticModel(), params: params(socialDensity: 4))
        let lights = build.container.children.filter { $0 is DirectionalLight }
        let models = build.container.children.filter { $0 is ModelEntity }
        #expect(lights.count == 3)
        #expect(models.count == 1 + 4)                       // the model + 4 orbs
        #expect(build.container.children.count == 1 + 3 + 4)
    }

    @Test func assembleZeroSocialDensityHasNoOrbs() {
        let build = ParametricWorldBuilder.assemble(model: syntheticModel(), params: params(socialDensity: 0))
        #expect(build.container.children.count == 1 + 3)     // model + 3 lights, no orbs
    }

    @Test func assembleFramingDerivesFromModelBounds() {
        let build = ParametricWorldBuilder.assemble(model: syntheticModel(), params: params())
        #expect(abs(build.span - 2) < 0.05)                  // box size 2 → span 2
        #expect(abs(build.eye.y - 0.3) < 0.05)               // center.y + extents.y * 0.15
    }

    @Test func assembleLightIntensitiesFollowMultipliers() {
        let build = ParametricWorldBuilder.assemble(model: syntheticModel(), params: params(lightIntensity: 1000))
        let intensities = build.container.children
            .compactMap { ($0 as? DirectionalLight)?.light.intensity }
            .sorted()
        #expect(intensities.count == 3)
        #expect(abs((intensities.max() ?? 0) - 1000) < 1)    // mult 1.0
        #expect(abs((intensities.min() ?? 0) - 350) < 1)     // mult 0.35
    }

    // MARK: - companionOrbs

    @Test func companionOrbsCountAndPerimeterPlacement() {
        let bounds = BoundingBox(min: SIMD3<Float>(-1, -1, -1), max: SIMD3<Float>(1, 1, 1))
        #expect(ParametricWorldBuilder.companionOrbs(count: 0, bounds: bounds, span: 2).isEmpty)

        let orbs = ParametricWorldBuilder.companionOrbs(count: 4, bounds: bounds, span: 2)
        #expect(orbs.count == 4)
        // orb[0] at angle 0 → (center.x + perimeter, floorY, center.z);
        // perimeter = max(extents.x, extents.z) * 0.45 = 0.9 ; floorY = min.y + span*0.05 = -0.9
        #expect(abs(orbs[0].position.x - 0.9) < 1e-4)
        #expect(abs(orbs[0].position.y - (-0.9)) < 1e-4)
        #expect(abs(orbs[0].position.z - 0) < 1e-4)
    }

    // MARK: - applySaturation

    @Test func applySaturationDesaturatesPhysicallyBasedMaterial() {
        var pbm = PhysicallyBasedMaterial()
        pbm.baseColor.tint = .red
        let entity = ModelEntity(mesh: .generateBox(size: 1), materials: [pbm])

        ParametricWorldBuilder.applySaturation(entity, saturation: 0.5)   // amount 0.5

        let rgb = components((entity.model?.materials.first as? PhysicallyBasedMaterial)?.baseColor.tint)
        #expect(abs(rgb.r - 0.606) < 0.01)   // greyed(.red, 0.5)
        #expect(abs(rgb.g - 0.106) < 0.01)
    }

    @Test func applySaturationIsNoOpAtFullSaturation() {
        var pbm = PhysicallyBasedMaterial()
        pbm.baseColor.tint = .red
        let entity = ModelEntity(mesh: .generateBox(size: 1), materials: [pbm])

        ParametricWorldBuilder.applySaturation(entity, saturation: 1.1)   // amount ≤ 0 → early return

        let rgb = components((entity.model?.materials.first as? PhysicallyBasedMaterial)?.baseColor.tint)
        #expect(abs(rgb.r - 1) < 0.01)
        #expect(abs(rgb.g - 0) < 0.01)
    }

    @Test func applySaturationDesaturatesUnlitMaterial() {
        let entity = ModelEntity(mesh: .generateBox(size: 1), materials: [UnlitMaterial(color: .blue)])
        ParametricWorldBuilder.applySaturation(entity, saturation: 0.5)
        let rgb = components((entity.model?.materials.first as? UnlitMaterial)?.color.tint)
        #expect(rgb.b < 1.0)   // blue pulled toward grey
        #expect(rgb.r > 0.0)   // grey adds some red
    }
}

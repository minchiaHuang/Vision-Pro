import RealityKit
import UIKit

/// Assembles the parametric USDZ world (model + lights + companion orbs) shared by both
/// platforms. iOS (`ParametricWorldView`) adds a `PerspectiveCamera` + `WorldCameraRig` on top;
/// visionOS (`ImmersiveWorldView`) positions the container relative to the origin and relies on
/// head tracking. All scene contents are parented under a single `container` entity so the
/// caller can place the whole world with one transform.
struct ParametricWorldBuild {
    let container: Entity   // model + lights + orbs, all parented here
    let bounds: BoundingBox
    let span: Float
    let eye: SIMD3<Float>
}

enum ParametricWorldBuilder {
    /// Loads the archetype USDZ and tunes it from `params`:
    ///   - axis 4: three DirectionalLights with intensity + colour temperature
    ///   - axis 1: ambient companion orbs (social density)
    /// Returns the assembled container plus framing info, or `nil` if the USDZ fails to load
    /// (each caller shows its own failure state). Saturation (axis 4) is applied by the caller
    /// — iOS via a SwiftUI overlay; visionOS via `applySaturation(_:saturation:)` (below).
    @MainActor
    static func build(params: WorldParams) async -> ParametricWorldBuild? {
        guard let model = try? await Entity(named: params.archetype.usdzName) else {
            return nil
        }

        let container = Entity()
        container.addChild(model)

        let bounds = model.visualBounds(relativeTo: nil)
        let span = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let eye = SIMD3<Float>(bounds.center.x,
                               bounds.center.y + bounds.extents.y * 0.15,
                               bounds.center.z)

        // axis 4: three directional lights with intensity + colour temperature.
        let warmth = colorFromKelvin(params.colorTemperature)
        for (dir, mult): (SIMD3<Float>, Float) in [
            ([1, 1, 1], 1.0), ([-1, 0.6, -0.6], 0.55), ([0, 0.4, 1], 0.35)
        ] {
            let light = DirectionalLight()
            light.light.intensity = params.lightIntensity * mult
            light.light.color = warmth
            light.look(at: .zero, from: dir, relativeTo: nil)
            container.addChild(light)
        }

        // axis 1: companion orbs placed on the floor perimeter.
        for orb in companionOrbs(count: params.socialDensity, bounds: bounds, span: span) {
            container.addChild(orb)
        }

        return ParametricWorldBuild(container: container, bounds: bounds, span: span, eye: eye)
    }

    /// axis 4 saturation for the visionOS immersive path. There is no full-screen
    /// post-process / `.blendMode(.saturation)` overlay inside an immersive `RealityView`
    /// (iOS uses one), so we bake the effect into the loaded model's materials: each
    /// material tint is lerped toward its luminance grey by `1 - saturation`, matching the
    /// iOS overlay mapping (saturation 1.1 → full colour, 0.5 → ~50% desaturated).
    ///
    /// Limitation: a tint multiply cannot desaturate *textured* surfaces, so heavily
    /// textured archetypes desaturate less than the iOS filter. A faithful match would need
    /// a `ShaderGraphMaterial` swap feeding the original textures — deferred.
    @MainActor
    static func applySaturation(_ root: Entity, saturation: Double) {
        let amount = Float(max(0, min(1, 1 - saturation)))   // 0 = full colour … 1 = grey
        guard amount > 0.001 else { return }
        forEachModelEntity(root) { entity in
            guard var model = entity.model else { return }
            model.materials = model.materials.map { desaturate($0, amount: amount) }
            entity.model = model
        }
    }

    /// Depth-first walk applying `body` to every `ModelEntity` under `entity` (inclusive).
    @MainActor
    private static func forEachModelEntity(_ entity: Entity, _ body: (ModelEntity) -> Void) {
        if let model = entity as? ModelEntity { body(model) }
        for child in entity.children { forEachModelEntity(child, body) }
    }

    /// Lerps a material's tint toward its perceptual grey by `amount` (0…1). Handles the
    /// material types the parametric world produces — `PhysicallyBasedMaterial` (loaded USDZ)
    /// and `UnlitMaterial` (companion orbs); others pass through unchanged.
    private static func desaturate(_ material: RealityKit.Material, amount: Float) -> RealityKit.Material {
        if var m = material as? PhysicallyBasedMaterial {
            m.baseColor.tint = greyed(m.baseColor.tint, amount: amount)
            return m
        }
        if var m = material as? UnlitMaterial {
            m.color.tint = greyed(m.color.tint, amount: amount)
            return m
        }
        return material
    }

    /// Blends `color` toward its Rec. 709 luminance grey by `amount`, preserving alpha.
    private static func greyed(_ color: UIColor, amount: Float) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            color.getWhite(&w, alpha: &a); r = w; g = w; b = w
        }
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let t = CGFloat(amount)
        return UIColor(red: r + (lum - r) * t,
                       green: g + (lum - g) * t,
                       blue: b + (lum - b) * t,
                       alpha: a)
    }

    /// 3-keyframe linear interpolation of Kelvin → UIColor.
    /// 3500 K = amber warm, 5500 K = neutral white, 7000 K = cool blue-white.
    static func colorFromKelvin(_ kelvin: Float) -> UIColor {
        if kelvin <= 5500 {
            let t = CGFloat((kelvin - 3500) / (5500 - 3500))
            return UIColor(red: 1.0, green: 0.76 + 0.24 * t, blue: 0.44 + 0.56 * t, alpha: 1)
        } else {
            let t = CGFloat((kelvin - 5500) / (7000 - 5500))
            return UIColor(red: 1.0 - 0.15 * t, green: 1.0 - 0.07 * t, blue: 1.0, alpha: 1)
        }
    }

    /// Returns evenly-spaced glow-orb ModelEntities on the scene's floor perimeter.
    /// `count == 0` returns empty (no companions). Used for axis 1 social density.
    @MainActor
    static func companionOrbs(count: Int, bounds: BoundingBox, span: Float) -> [ModelEntity] {
        guard count > 0 else { return [] }
        let perimeter = max(bounds.extents.x, bounds.extents.z) * 0.45
        let floorY = bounds.min.y + span * 0.05
        let orbRadius = span * 0.02
        return (0..<count).map { i in
            let angle = Float(i) * (.pi * 2 / Float(count))
            let mesh = MeshResource.generateSphere(radius: orbRadius)
            let mat = UnlitMaterial(color: UIColor(white: 0.9, alpha: 0.8))
            let orb = ModelEntity(mesh: mesh, materials: [mat])
            orb.position = SIMD3<Float>(bounds.center.x + cos(angle) * perimeter,
                                         floorY,
                                         bounds.center.z + sin(angle) * perimeter)
            return orb
        }
    }
}

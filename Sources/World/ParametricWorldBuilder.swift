import RealityKit
import UIKit

struct ParametricWorldBuild {
    let container: Entity
    let bounds: BoundingBox
    let span: Float
    let eye: SIMD3<Float>
}

enum ParametricWorldBuilder {

    @MainActor
    static func build(params: WorldParams,
                      galleryPhotos: [UIImage] = []) async -> ParametricWorldBuild? {
        guard let model = try? await Entity(named: params.archetype.usdzName) else {
            return nil
        }

        let container = Entity()
        container.addChild(model)

        if params.archetype == .artGallery {
            let photos = galleryPhotos.isEmpty
                ? await loadGalleryPhotoTextures()
                : texturesFrom(galleryPhotos)
            applyGalleryPhotos(model, textures: photos)
        }

        let bounds = model.visualBounds(relativeTo: nil)
        let span = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let eye = SIMD3<Float>(bounds.center.x,
                               bounds.center.y + bounds.extents.y * 0.15,
                               bounds.center.z)

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

        for orb in companionOrbs(count: params.socialDensity, bounds: bounds, span: span) {
            container.addChild(orb)
        }

        return ParametricWorldBuild(container: container, bounds: bounds, span: span, eye: eye)
    }

    @MainActor
    static func applySaturation(_ root: Entity, saturation: Double) {
        let amount = Float(max(0, min(1, 1 - saturation)))
        guard amount > 0.001 else { return }
        forEachModelEntity(root) { entity in
            guard var model = entity.model else { return }
            model.materials = model.materials.map { desaturate($0, amount: amount) }
            entity.model = model
        }
    }

    // MARK: - Gallery frame photos

    @MainActor
    static func texturesFrom(_ images: [UIImage]) -> [TextureResource] {
        images.compactMap { image in
            guard let cg = image.cgImage else { return nil }
            return try? TextureResource(image: cg, options: .init(semantic: .color))
        }
    }

    @MainActor
    static func loadGalleryPhotoTextures() async -> [TextureResource] {
        var urls: [URL] = []
        for ext in ["jpg", "jpeg", "png"] {
            let found = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            urls += found.filter {
                $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("beach")
            }
        }
        urls.sort { $0.lastPathComponent < $1.lastPathComponent }

        var textures: [TextureResource] = []
        for url in urls {
            if let tex = try? await TextureResource(contentsOf: url,
                                                    options: .init(semantic: .color)) {
                textures.append(tex)
            }
        }
        return textures
    }

    @MainActor
    static func applyGalleryPhotos(_ root: Entity, textures: [TextureResource]) {
        guard !textures.isEmpty else { return }

        var frames: [ModelEntity] = []
        forEachModelEntity(root) { entity in
            let name = entity.name.lowercased()
            guard name.contains("bake") else { return }
            if name.contains("door") || name.contains("butterfly") { return }
            frames.append(entity)
        }
        frames.sort { $0.name < $1.name }

        #if DEBUG
        print("[Gallery] Found \(frames.count) frames:")
        frames.enumerated().forEach { print("  \($0.offset): \($0.element.name)") }
        #endif

        for (index, frame) in frames.enumerated() {
            if index < textures.count {
                guard var model = frame.model else { continue }
                let texture = textures[index]
                var unlit = UnlitMaterial()
                unlit.color = .init(tint: .white, texture: .init(texture))
                model.materials = Array(repeating: unlit, count: model.materials.count)
                frame.model = model
            } else {
                frame.isEnabled = false
            }
        }
    }

    @MainActor
    private static func forEachModelEntity(_ entity: Entity, _ body: (ModelEntity) -> Void) {
        if let model = entity as? ModelEntity { body(model) }
        for child in entity.children { forEachModelEntity(child, body) }
    }

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

    static func colorFromKelvin(_ kelvin: Float) -> UIColor {
        if kelvin <= 5500 {
            let t = CGFloat((kelvin - 3500) / (5500 - 3500))
            return UIColor(red: 1.0, green: 0.76 + 0.24 * t, blue: 0.44 + 0.56 * t, alpha: 1)
        } else {
            let t = CGFloat((kelvin - 5500) / (7000 - 5500))
            return UIColor(red: 1.0 - 0.15 * t, green: 1.0 - 0.07 * t, blue: 1.0, alpha: 1)
        }
    }

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

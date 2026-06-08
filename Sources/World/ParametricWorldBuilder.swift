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
    /// Uniform scale applied to the gallery USDZ (see `build`). 1.0 = model's authored size
    /// (~10 m room, 3 m ceiling). The headset eye sits at a fixed ~1.6 m, so the authored room
    /// reads as cavernous ("everything too big"); shrinking the whole world makes the viewer feel
    /// correctly present. 0.7 ≈ a 7 m room / 2.1 m ceiling. Tunable.
    static let galleryWorldScale: Float = 0.7

    /// Loads the archetype USDZ and tunes it from `params`:
    ///   - axis 4: three DirectionalLights with intensity + colour temperature
    ///   - axis 1: ambient companion orbs (social density)
    /// Returns the assembled container plus framing info, or `nil` if the USDZ fails to load
    /// (each caller shows its own failure state). Saturation (axis 4) is applied by the caller
    /// — iOS via a SwiftUI overlay; visionOS via `applySaturation(_:saturation:)` (below).
    @MainActor
    static func build(params: WorldParams,
                      galleryPhotos: [UIImage] = []) async -> ParametricWorldBuild? {
        guard let model = try? await Entity(named: params.archetype.usdzName) else {
            return nil
        }

        // Gallery scale. The Art_Gallery_E_2020 model is authored ~realistically (≈10 m-wide
        // room, 3 m ceiling) but reads as oversized/cavernous in headset because its artworks are
        // small (~0.6 m) and hung low, leaving tall blank walls. Shrink the whole world uniformly
        // so the human feels correctly sized inside it. Tunable — raise toward 1.0 for a larger
        // hall, lower for a more intimate room. Applied before bounds so floor-align, span and
        // locomotion all stay consistent.
        if params.archetype == .artGallery {
            model.scale = SIMD3(repeating: galleryWorldScale)
        }

        let container = Entity()
        container.addChild(model)

        // Gallery only: swap the baked artwork on the wall frames. Prefer AI-generated photos
        // (the Hero's-Journey series) when supplied; otherwise fall back to the bundled beach
        // placeholders. The frames bind their image to `emissiveColor` (diffuse is black), so
        // `applyGalleryPhotos` reuses each mesh's UVs to keep correct on-wall placement.
        if params.archetype == .artGallery {
            let photos = galleryPhotos.isEmpty
                ? await loadGalleryPhotoTextures()
                : texturesFrom(galleryPhotos)
            applyGalleryPhotos(model, textures: photos)
        }

        // Placement bounds. For the gallery, exclude the far backdrop meshes (the city seen
        // through the window: `outside`/`glass`/`window`) so the user is centred on the *room*,
        // not pulled toward the window and sunk below the floor. The Art_Gallery_E_2020 model's
        // backdrop otherwise pushes the z-centre back ~0.58 m and the floor down ~0.23 m.
        let bounds = params.archetype == .artGallery
            ? interiorBounds(of: model, excluding: ["outside", "glass", "window"])
            : model.visualBounds(relativeTo: nil)
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

    // MARK: - Gallery frame photos

    /// Converts in-memory images (the AI-generated Hero's-Journey series) into textures, in the
    /// same order. Images that can't produce a `CGImage`/`TextureResource` are skipped.
    ///
    /// Each image is flipped vertically first: the gallery frames display the photo through an
    /// `UnlitMaterial.color` texture, which samples the V axis from the opposite origin to the
    /// USDZ's original PBR `emissiveColor` binding — so an un-flipped image renders upside down.
    @MainActor
    static func texturesFrom(_ images: [UIImage]) -> [TextureResource] {
        images.compactMap { image in
            guard let cg = flippedVertically(image) else { return nil }
            return try? TextureResource(image: cg, options: .init(semantic: .color))
        }
    }

    /// Returns `image` flipped top-to-bottom as a `CGImage`. Drawing through a renderer also
    /// normalises any `imageOrientation` metadata, so the result is a plain, upright bitmap once
    /// the texture's V-axis sampling is accounted for (see `texturesFrom`).
    @MainActor
    private static func flippedVertically(_ image: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let flipped = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: image.size.height)
            cg.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return flipped.cgImage
    }

    /// Loads every bundled `beach*` image (jpg/jpeg/png) as a texture, sorted by filename
    /// (beach 2, beach 4, beach 7, …) so the photo-to-frame assignment is stable. Enumerating
    /// the bundle — rather than hard-coding names — means whatever beach files are dropped in
    /// are picked up automatically. Skips any that fail to load. Routed through `texturesFrom`
    /// so the bundled placeholders get the same vertical flip as the AI-generated photos.
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

        let images = urls.compactMap { UIImage(contentsOfFile: $0.path) }
        return texturesFrom(images)
    }

    /// Replaces every wall-frame mesh's material with an `UnlitMaterial` showing a beach photo,
    /// cycling through `textures`. The whole gallery is unlit-baked (each material feeds its
    /// texture into emissiveColor over a black diffuse), so an UnlitMaterial reproduces the flat,
    /// evenly-lit look and renders the photo reliably — mutating the PBR emissive texture in place
    /// instead rendered flat white. Reusing each mesh's existing UVs keeps the photo on the wall
    /// with correct placement, orientation, perspective, and scale.
    ///
    /// Frames are identified by mesh name containing "painting" (the Art_Gallery_E_2020 model's
    /// artwork meshes are named `paintings_01_0` … `paintings_08_0`). The `canvas` and `material`
    /// meshes (`paintings_canvas_0`, `paintings_Material #93_0`) are the mounts, not the picture
    /// surface, so they are excluded. Walls, floor, bench, lamps, etc. have no "painting" in
    /// their names. Sorting by name maps `paintings_01…08` to beat order.
    @MainActor
    static func applyGalleryPhotos(_ root: Entity, textures: [TextureResource]) {
        guard !textures.isEmpty else { return }

        var frames: [ModelEntity] = []
        forEachModelEntity(root) { entity in
            let name = entity.name.lowercased()
            guard name.contains("painting") else { return }
            if name.contains("canvas") || name.contains("material") { return }
            frames.append(entity)
        }
        frames.sort { $0.name < $1.name }

        for (index, frame) in frames.enumerated() {
            guard var model = frame.model else { continue }
            let texture = textures[index % textures.count]
            var unlit = UnlitMaterial()
            unlit.color = .init(tint: .white, texture: .init(texture))
            model.materials = Array(repeating: unlit, count: model.materials.count)
            frame.model = model
        }
    }

    /// Depth-first walk applying `body` to every `ModelEntity` under `entity` (inclusive).
    @MainActor
    private static func forEachModelEntity(_ entity: Entity, _ body: (ModelEntity) -> Void) {
        if let model = entity as? ModelEntity { body(model) }
        for child in entity.children { forEachModelEntity(child, body) }
    }

    /// World-space bounds of `root`'s `ModelEntity`s whose name contains none of `tokens`
    /// (case-insensitive). Lets the gallery be framed on its room geometry while ignoring the
    /// distant backdrop (city plane / glass / window) that would otherwise skew the centre and
    /// floor. Falls back to the full visual bounds if nothing qualifies.
    @MainActor
    static func interiorBounds(of root: Entity, excluding tokens: [String]) -> BoundingBox {
        var box: BoundingBox?
        forEachModelEntity(root) { entity in
            let name = entity.name.lowercased()
            if tokens.contains(where: { name.contains($0) }) { return }
            let b = entity.visualBounds(relativeTo: nil)
            box = box.map { $0.union(b) } ?? b
        }
        return box ?? root.visualBounds(relativeTo: nil)
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

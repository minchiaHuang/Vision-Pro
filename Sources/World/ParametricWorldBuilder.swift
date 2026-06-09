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
    static func build(params: WorldParams,
                      galleryPhotos: [UIImage] = []) async -> ParametricWorldBuild? {
        guard let model = try? await Entity(named: params.archetype.usdzName) else {
            return nil
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

        // BA396 only: the 6 portrait walls are a single mesh sharing one 3x2 atlas texture,
        // so we can't bind one image per wall like the gallery. Composite the generated beat
        // images into one atlas matching the portrait UV tiles and swap the Portraits material.
        // When no photos are supplied (dev-menu direct entry) leave BA396's baked PortraitUV.
        if params.archetype == .ba396Museum, !galleryPhotos.isEmpty {
            applyBA396Portraits(model, images: galleryPhotos)
        }

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
    /// Frames are identified by mesh name containing "bake" (the baked artworks — note asset
    /// typos: "manual"/"manuel"/"manua"), excluding the corridor door and the butterfly wings.
    /// Walls, floor, plant, curtains, dream-catchers, etc. have no "bake" in their mesh names.
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

        for (index, frame) in frames.enumerated() {
            guard var model = frame.model else { continue }
            let texture = textures[index % textures.count]
            var unlit = UnlitMaterial()
            unlit.color = .init(tint: .white, texture: .init(texture))
            model.materials = Array(repeating: unlit, count: model.materials.count)
            frame.model = model
        }
    }

    // MARK: - BA396 portrait walls

    /// The 6 portrait UV tiles of BA396's `Portraits` mesh (网格_006), as
    /// (uMin, uMax, vMin, vMax) — a 3-column x 2-row atlas decoded from the USDZ. The whole
    /// wall set is one mesh sharing one material, so each picture is a sub-rect of one texture.
    /// Order: bottom row left->right, then top row left->right.
    /// Physical aspect (width / height) of each BA396 portrait wall quad, measured from the
    /// `网格_006` mesh: each quad is ~0.775 wide x ~0.441 tall ≈ 1.76:1 (≈16:9 landscape).
    /// The generated photos are 1.5:1, so they are center-cropped to this before compositing,
    /// to fill each frame without horizontal stretch.
    private static let ba396PortraitAspect: CGFloat = 0.775 / 0.441

    private static let ba396PortraitTiles: [(uMin: CGFloat, uMax: CGFloat, vMin: CGFloat, vMax: CGFloat)] = [
        (0.011, 0.289, 0.013, 0.487),  // col 0, bottom
        (0.311, 0.589, 0.013, 0.487),  // col 1, bottom
        (0.611, 0.889, 0.013, 0.487),  // col 2, bottom
        (0.011, 0.289, 0.513, 0.987),  // col 0, top
        (0.311, 0.589, 0.513, 0.987),  // col 1, top
        (0.611, 0.889, 0.513, 0.987),  // col 2, top
    ]

    /// BA396's portrait UVs are authored rotated 90° (the baked PortraitUV placeholder text is
    /// sideways), so an upright image renders turned on the wall. We pre-rotate each image 90°
    /// when compositing to cancel it. Flip this if the walls come out upside-down on device.
    private static let ba396PortraitRotateClockwise = false
    /// Per-tile horizontal mirror (some walls' UVs are flipped). Photo mirroring is usually
    /// imperceptible, so this defaults off; set an index true if that wall looks left-right reversed.
    private static let ba396PortraitMirror: [Bool] = [false, false, false, false, false, false]

    /// Composites the generated beat `images` into one atlas matching `ba396PortraitTiles` and
    /// swaps it onto BA396's `Portraits` mesh material, so each of the 6 walls shows a full
    /// image (cycling if fewer than 6 supplied). No-op if no portrait mesh is found.
    @MainActor
    static func applyBA396Portraits(_ root: Entity, images: [UIImage]) {
        guard !images.isEmpty, let atlas = ba396PortraitAtlas(images) else { return }

        var unlit = UnlitMaterial()
        unlit.color = .init(tint: .white, texture: .init(atlas))

        forEachModelEntity(root) { entity in
            // The Portraits surface is mesh 网格_006 under Xform "Portraits"; the PaintingFrame
            // is 网格_005 under "Portraits_PaintingFrame_0" (also contains "portraits"), so match
            // on portrait/网格_006 while excluding frame/网格_005 regardless of which name
            // RealityKit kept (Xform name vs exported mesh id).
            let isPortrait = selfOrAncestor(entity, contains: "portrait")
                          || selfOrAncestor(entity, contains: "网格_006")
            let isFrame = selfOrAncestor(entity, contains: "frame")
                       || selfOrAncestor(entity, contains: "网格_005")
            guard isPortrait, !isFrame else { return }
            guard var model = entity.model else { return }
            model.materials = Array(repeating: unlit, count: max(1, model.materials.count))
            entity.model = model
        }
    }

    /// Builds the 3x2 portrait atlas as a `TextureResource`. Each image is drawn into its UV
    /// tile's pixel rect; UV is mapped with V increasing upward (pixel y = (1 - v) * H).
    /// If the walls render vertically flipped on device, wrap the result through
    /// `flippedVertically` (one-line change).
    @MainActor
    static func ba396PortraitAtlas(_ images: [UIImage]) -> TextureResource? {
        let side: CGFloat = 2048
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)

        let atlas = renderer.image { ctx in
            UIColor(white: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let cg = ctx.cgContext
            for (i, tile) in ba396PortraitTiles.enumerated() {
                // Center-crop to the frame's physical aspect, then rotate 90° (cancelling the
                // wall's authored UV rotation) and fill the tile. The quad samples the whole
                // tile, so the result lands as an upright, undistorted landscape photo.
                let framed = centerCropped(images[i % images.count], toAspect: ba396PortraitAspect)
                let rect = CGRect(x: tile.uMin * side,
                                  y: (1 - tile.vMax) * side,
                                  width: (tile.uMax - tile.uMin) * side,
                                  height: (tile.vMax - tile.vMin) * side)
                cg.saveGState()
                cg.translateBy(x: rect.midX, y: rect.midY)
                cg.rotate(by: ba396PortraitRotateClockwise ? -.pi / 2 : .pi / 2)
                if ba396PortraitMirror[i] { cg.scaleBy(x: -1, y: 1) }
                // In the rotated frame the tile's width/height swap, so the landscape image fills it.
                framed.draw(in: CGRect(x: -rect.height / 2, y: -rect.width / 2,
                                       width: rect.height, height: rect.width))
                cg.restoreGState()
            }
        }
        guard let cg = atlas.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    /// Returns the largest centered crop of `image` matching `aspect` (width / height). When the
    /// target is wider than the source it keeps full width and trims top/bottom (and vice versa),
    /// so the result fills its frame with no stretch — at the cost of a small edge crop.
    @MainActor
    private static func centerCropped(_ image: UIImage, toAspect aspect: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return image }
        let cropW: CGFloat, cropH: CGFloat
        if w / h > aspect {                 // source too wide → trim sides
            cropH = h; cropW = h * aspect
        } else {                            // source too tall → trim top/bottom
            cropW = w; cropH = w / aspect
        }
        let origin = CGPoint(x: (w - cropW) / 2, y: (h - cropH) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: cropW, height: cropH), format: format).image { _ in
            image.draw(in: CGRect(x: -origin.x, y: -origin.y, width: w, height: h))
        }
    }

    /// True if `entity` or any of its ancestors has a name containing `token` (case-insensitive).
    /// Used to identify BA396's Portraits mesh whose own name is the exported mesh id (网格_006)
    /// but whose parent Xform is named "Portraits".
    @MainActor
    private static func selfOrAncestor(_ entity: Entity, contains token: String) -> Bool {
        var node: Entity? = entity
        while let n = node {
            if n.name.lowercased().contains(token) { return true }
            node = n.parent
        }
        return false
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

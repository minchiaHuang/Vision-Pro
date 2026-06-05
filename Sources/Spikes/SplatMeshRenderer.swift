#if os(visionOS)

import Metal
import MetalKit
import ModelIO
import CompositorServices
import MetalSplatter
import simd
import os

/// Renders a single USDZ model *inside* the CompositorServices splat world. The splat
/// pass (MetalSplatter) clears color + depth and writes splat depth, so this renderer
/// composites the mesh in its OWN render pass AFTER the splat render, loading (not
/// clearing) the same color + depth textures. Because the splat pass stores depth, the
/// mesh and the splats occlude each other correctly (reversed-Z → `.greater`).
///
/// Stereo matches MetalSplatter: one MVP per eye, selected in-shader via
/// `[[amplification_id]]`, driven by `setVertexAmplificationCount(_:viewMappings:)`.
///
/// `@unchecked Sendable`: the loaded model is published once under `lock` and then
/// adopted + owned by the render thread, mirroring `SplatVisionRenderer`'s pattern.
final class SplatMeshRenderer: @unchecked Sendable {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VisitingArtisan",
                                    category: "SplatMesh")

    /// Largest model dimension is scaled to this many metres (a hand-held hero object).
    private static let targetSize: Float = 0.6

    /// Keep in sync with `MeshVertexUniforms` in SplatMeshShaders.metal.
    private struct VertexUniforms {
        var modelViewProjection: (simd_float4x4, simd_float4x4) // [2], one per eye
        var model: simd_float4x4
    }

    private struct LoadedModel {
        let meshes: [MTKMesh]
        let textures: [[MTLTexture]] // [meshIndex][submeshIndex], always populated
        let normalize: simd_float4x4 // recentre + uniform scale to targetSize
    }

    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let defaultTexture: MTLTexture

    private let lock = NSLock()
    private var pendingModel: LoadedModel?
    private var model: LoadedModel?            // render-thread owned after adoption

    /// World placement (in calibrated/splat space) set by the owner before adoption.
    /// Final model matrix = `worldPlacement * normalize`.
    var worldPlacement: simd_float4x4 = matrix_identity_float4x4

    init(device: MTLDevice, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) throws {
        self.device = device

        // Interleaved layout: position(0) normal(12) uv(24), stride 32. Used for both the
        // MDLAsset load and the pipeline vertex descriptor so they match exactly.
        let mdlVD = MDLVertexDescriptor()
        mdlVD.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                 format: .float3, offset: 0, bufferIndex: 0)
        mdlVD.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                 format: .float3, offset: 12, bufferIndex: 0)
        mdlVD.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                 format: .float2, offset: 24, bufferIndex: 0)
        (mdlVD.layouts[0] as! MDLVertexBufferLayout).stride = 32
        Self.sharedVertexDescriptor = mdlVD

        guard let library = device.makeDefaultLibrary() else {
            throw MeshError.noLibrary
        }
        let pdesc = MTLRenderPipelineDescriptor()
        pdesc.vertexFunction = library.makeFunction(name: "splatMeshVertex")
        pdesc.fragmentFunction = library.makeFunction(name: "splatMeshFragment")
        pdesc.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlVD)
        pdesc.colorAttachments[0].pixelFormat = colorFormat
        pdesc.depthAttachmentPixelFormat = depthFormat
        pdesc.rasterSampleCount = 1
        pdesc.maxVertexAmplificationCount = 2
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pdesc)

        let ddesc = MTLDepthStencilDescriptor()
        ddesc.depthCompareFunction = .greater // reversed-Z (splat clears depth to 0 = far)
        ddesc.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: ddesc) else {
            throw MeshError.noDepthState
        }
        self.depthState = depthState
        self.defaultTexture = Self.makeSolidTexture(device: device, color: SIMD4(1, 1, 1, 1))
    }

    /// Set once at construction so `load()` (off-thread) reuses the same descriptor.
    nonisolated(unsafe) private static var sharedVertexDescriptor = MDLVertexDescriptor()

    private enum MeshError: Error { case noLibrary, noDepthState }

    // MARK: - Loading

    /// Kicks off an off-thread USDZ load; the render thread adopts it when ready.
    /// Failure is non-fatal — the world simply renders without the model.
    func loadModel(url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let loaded = try self.load(url: url)
                self.lock.withLock { self.pendingModel = loaded }
                Self.log.info("Loaded mesh model from \(url.lastPathComponent)")
            } catch {
                Self.log.error("Failed to load mesh: \(error.localizedDescription)")
            }
        }
    }

    private func load(url: URL) throws -> LoadedModel {
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url,
                             vertexDescriptor: Self.sharedVertexDescriptor,
                             bufferAllocator: allocator)
        asset.loadTextures()

        // Flatten all meshes (node transforms are not applied — fine for a single hero
        // object; bounds below are computed from the same flattened set so they match).
        guard let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh],
              !mdlMeshes.isEmpty else {
            throw MeshError.noLibrary
        }

        let loader = MTKTextureLoader(device: device)
        var mtkMeshes: [MTKMesh] = []
        var textures: [[MTLTexture]] = []
        var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for mdlMesh in mdlMeshes {
            // Ensure lighting normals exist, then re-assert our layout.
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
            mdlMesh.vertexDescriptor = Self.sharedVertexDescriptor

            let box = mdlMesh.boundingBox
            minB = simd_min(minB, box.minBounds)
            maxB = simd_max(maxB, box.maxBounds)

            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
            mtkMeshes.append(mtkMesh)

            // One base-color texture per submesh, in MTKSubmesh order (== MDLSubmesh order).
            var meshTextures: [MTLTexture] = []
            let mdlSubmeshes = (mdlMesh.submeshes as? [MDLSubmesh]) ?? []
            for i in 0..<mtkMesh.submeshes.count {
                let material = i < mdlSubmeshes.count ? mdlSubmeshes[i].material : nil
                meshTextures.append(baseColorTexture(for: material, loader: loader))
            }
            textures.append(meshTextures)
        }

        // Recentre on bounds centre, scale largest dimension to targetSize.
        let center = (minB + maxB) * 0.5
        let extent = maxB - minB
        let maxDim = max(max(extent.x, extent.y), max(extent.z, 0.0001))
        let scale = Self.targetSize / maxDim
        let normalize = Self.scaleMatrix(scale) * Self.translation(-center.x, -center.y, -center.z)

        return LoadedModel(meshes: mtkMeshes, textures: textures, normalize: normalize)
    }

    private func baseColorTexture(for material: MDLMaterial?, loader: MTKTextureLoader) -> MTLTexture {
        guard let material, let prop = material.property(with: .baseColor) else { return defaultTexture }
        switch prop.type {
        case .texture:
            if let mdlTex = prop.textureSamplerValue?.texture,
               let tex = try? loader.newTexture(texture: mdlTex,
                                                options: [.generateMipmaps: true, .SRGB: true]) {
                return tex
            }
            return defaultTexture
        case .float4:
            return Self.makeSolidTexture(device: device, color: prop.float4Value)
        case .float3:
            let c = prop.float3Value
            return Self.makeSolidTexture(device: device, color: SIMD4(c.x, c.y, c.z, 1))
        default:
            return defaultTexture
        }
    }

    // MARK: - Encoding (called on the render thread, inside the drawables loop)

    /// Composites the model into the already-rendered splat frame. No-op until the model
    /// has loaded. Uses its own render pass that LOADs the splat color + depth.
    func encode(into commandBuffer: MTLCommandBuffer,
                colorTexture: MTLTexture,
                depthTexture: MTLTexture?,
                rasterizationRateMap: MTLRasterizationRateMap?,
                renderTargetArrayLength: Int,
                viewports: [SplatRenderer.ViewportDescriptor]) {
        if model == nil {
            lock.lock(); let pending = pendingModel; lock.unlock()
            if let pending { model = pending }
        }
        guard let model, !viewports.isEmpty else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = colorTexture
        rpd.colorAttachments[0].loadAction = .load
        rpd.colorAttachments[0].storeAction = .store
        if let depthTexture {
            rpd.depthAttachment.texture = depthTexture
            rpd.depthAttachment.loadAction = .load
            rpd.depthAttachment.storeAction = .store
        }
        rpd.rasterizationRateMap = rasterizationRateMap
        if renderTargetArrayLength > 0 {
            rpd.renderTargetArrayLength = renderTargetArrayLength
        }

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.label = "SplatMeshOverlay"
        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.back)
        enc.setFrontFacing(.counterClockwise)

        enc.setViewports(viewports.map(\.viewport))
        if viewports.count > 1 {
            let mappings = (0..<viewports.count).map { i in
                MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32(i),
                                                  renderTargetArrayIndexOffset: UInt32(i))
            }
            enc.setVertexAmplificationCount(viewports.count, viewMappings: mappings)
        }

        let modelMatrix = worldPlacement * model.normalize
        let eye0 = viewports[0]
        let eye1 = viewports.count > 1 ? viewports[1] : viewports[0]
        var uniforms = VertexUniforms(
            modelViewProjection: (eye0.projectionMatrix * eye0.viewMatrix * modelMatrix,
                                  eye1.projectionMatrix * eye1.viewMatrix * modelMatrix),
            model: modelMatrix)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 1)

        for (meshIndex, mesh) in model.meshes.enumerated() {
            for (bufferIndex, vb) in mesh.vertexBuffers.enumerated() {
                enc.setVertexBuffer(vb.buffer, offset: vb.offset, index: bufferIndex)
            }
            for (submeshIndex, submesh) in mesh.submeshes.enumerated() {
                enc.setFragmentTexture(model.textures[meshIndex][submeshIndex], index: 0)
                enc.drawIndexedPrimitives(type: submesh.primitiveType,
                                          indexCount: submesh.indexCount,
                                          indexType: submesh.indexType,
                                          indexBuffer: submesh.indexBuffer.buffer,
                                          indexBufferOffset: submesh.indexBuffer.offset)
            }
        }
        enc.endEncoding()
    }

    // MARK: - Helpers

    private static func makeSolidTexture(device: MTLDevice, color: SIMD4<Float>) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: 1, height: 1, mipmapped: false)
        let tex = device.makeTexture(descriptor: desc)!
        var px: [UInt8] = [UInt8(max(0, min(1, color.x)) * 255),
                           UInt8(max(0, min(1, color.y)) * 255),
                           UInt8(max(0, min(1, color.z)) * 255),
                           UInt8(max(0, min(1, color.w)) * 255)]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: &px, bytesPerRow: 4)
        return tex
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1, 0, 0, 0),
                                SIMD4(0, 1, 0, 0),
                                SIMD4(0, 0, 1, 0),
                                SIMD4(x, y, z, 1)))
    }

    private static func scaleMatrix(_ s: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(s, 0, 0, 0),
                                SIMD4(0, s, 0, 0),
                                SIMD4(0, 0, s, 0),
                                SIMD4(0, 0, 0, 1)))
    }
}

#endif // os(visionOS)

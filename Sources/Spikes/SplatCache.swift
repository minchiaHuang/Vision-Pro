#if os(visionOS)

import Foundation
import Metal
import MetalSplatter
import SplatIO
import simd
import os

/// Disk cache for decoded splat scenes. Stores GPU-ready `EncodedSplatPoint` bytes
/// plus framing matrices so cache hits skip both `readAll()` (30 s zstd decode) and
/// the `SplatChunk` encoding loop. Only the Metal buffer memcpy and `addChunk` remain.
///
/// Cache key encodes the resource name, app version, and flipUpsideDown flag so any
/// of those changes forces a cold decode.
enum SplatCache {

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app",
                                    category: "SplatCache")

    // MARK: - Cached data

    struct CachedScene {
        let calibration: simd_float4x4
        let locomotionPosition: SIMD3<Float>
        let locomotionSpan: Float
        let modelPlacement: simd_float4x4
        let pointCount: Int
        let shDegree: SHDegree
        let splatData: Data   // raw EncodedSplatPoint bytes
        let shData: Data      // raw Float16 bytes; empty if SH0
    }

    // MARK: - Cache directory + key

    private static var cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("splat-decoded", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func cachePath(for url: URL, flipUpsideDown: Bool) -> URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let name = url.isFileURL
            ? url.deletingPathExtension().lastPathComponent
            : String(format: "%llx", UInt64(bitPattern: Int64(url.absoluteString.hashValue)))
        let flip = flipUpsideDown ? "f" : "n"
        return cacheDir.appendingPathComponent("\(name)-v\(version)-\(flip).splatchache")
    }

    // MARK: - Load

    /// Returns the cached scene or `nil` on a miss. Throws only on corrupt data.
    static func loadScene(for url: URL, flipUpsideDown: Bool) throws -> CachedScene? {
        let path = cachePath(for: url, flipUpsideDown: flipUpsideDown)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path, options: .mappedIfSafe)
        return try deserialize(data)
    }

    // MARK: - Save

    /// Extracts raw bytes from the Metal buffers in `chunk` and writes the cache file.
    /// Safe to call from a detached background task.
    static func saveScene(
        chunk: SplatChunk,
        calibration: simd_float4x4,
        locomotionPosition: SIMD3<Float>,
        locomotionSpan: Float,
        modelPlacement: simd_float4x4,
        for url: URL,
        flipUpsideDown: Bool
    ) throws {
        let splatData = Data(bytes: chunk.splats.values,
                             count: chunk.splats.count * MemoryLayout<EncodedSplatPoint>.stride)
        let shData: Data = {
            guard let sh = chunk.shCoefficients else { return Data() }
            return Data(bytes: sh.values, count: sh.count * MemoryLayout<Float16>.stride)
        }()

        let scene = CachedScene(
            calibration: calibration,
            locomotionPosition: locomotionPosition,
            locomotionSpan: locomotionSpan,
            modelPlacement: modelPlacement,
            pointCount: chunk.splats.count,
            shDegree: chunk.shDegree,
            splatData: splatData,
            shData: shData
        )

        let path = cachePath(for: url, flipUpsideDown: flipUpsideDown)
        try serialize(scene).write(to: path, options: .atomic)
        log.info("SplatCache: saved \(chunk.splats.count) pts → \(path.lastPathComponent)")
    }

    // MARK: - Pre-warm

    /// Runs a full decode + cache write in the background if no cache exists yet.
    /// Called from OopsFlow when the quiz starts so vibrant_loft is ready by the time
    /// the user taps Enter World.
    static func warmIfNeeded(bundleResource: String, withExtension ext: String,
                             flipUpsideDown: Bool) async {
        guard let url = Bundle.main.url(forResource: bundleResource, withExtension: ext) else {
            log.warning("SplatCache: \(bundleResource).\(ext) not in bundle")
            return
        }
        let path = cachePath(for: url, flipUpsideDown: flipUpsideDown)
        guard !FileManager.default.fileExists(atPath: path.path) else {
            log.debug("SplatCache: warm already cached (\(path.lastPathComponent))")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.warning("SplatCache: no Metal device for warm"); return
        }
        log.info("SplatCache: pre-warming \(bundleResource).\(ext)")
        do {
            let rawPoints = try await AutodetectSceneReader(url).readAll()
            guard !rawPoints.isEmpty else { return }
            let points = downsample(rawPoints, to: 1_500_000)
            let (calibration, locomotion, modelPlacement) =
                SplatVisionRenderer.framing(points, flipUpsideDown: flipUpsideDown)
            let chunk = try SplatChunk(device: device, from: points)
            try saveScene(chunk: chunk,
                          calibration: calibration,
                          locomotionPosition: locomotion.position,
                          locomotionSpan: locomotion.span,
                          modelPlacement: modelPlacement,
                          for: url,
                          flipUpsideDown: flipUpsideDown)
        } catch {
            log.error("SplatCache: warm failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Downsample (mirrors SplatVisionRenderer)

    private static func downsample(_ points: [SplatPoint], to budget: Int) -> [SplatPoint] {
        guard points.count > budget else { return points }
        let stride = Int((Double(points.count) / Double(budget)).rounded(.up))
        var out = [SplatPoint]()
        out.reserveCapacity(points.count / stride + 1)
        var i = 0
        while i < points.count { out.append(points[i]); i += stride }
        return out
    }

    // MARK: - Serialization
    //
    // Format (little-endian):
    //   magic         8 B  "SPLATC01"
    //   pointCount    4 B  UInt32
    //   shDegreeRaw   1 B  UInt8
    //   calibration  64 B  16 × Float32 (column-major)
    //   locoPos      12 B  3 × Float32
    //   locoSpan      4 B  Float32
    //   modelPlacement 64 B 16 × Float32
    //   splatLen      8 B  UInt64
    //   shLen         8 B  UInt64
    //   splatData     splatLen B
    //   shData        shLen B

    private static let magic = Data("SPLATC01".utf8)

    private static func serialize(_ s: CachedScene) -> Data {
        var w = Writer()
        w.append(magic)
        w.write(UInt32(s.pointCount))
        w.write(s.shDegree.rawValue)
        w.writeFloat4x4(s.calibration)
        w.writeFloat3(s.locomotionPosition)
        w.write(s.locomotionSpan)
        w.writeFloat4x4(s.modelPlacement)
        w.write(UInt64(s.splatData.count))
        w.write(UInt64(s.shData.count))
        w.data.append(s.splatData)
        w.data.append(s.shData)
        return w.data
    }

    private static func deserialize(_ data: Data) throws -> CachedScene {
        guard data.count >= magic.count, data.prefix(magic.count) == magic else {
            throw CacheError.badMagic
        }
        var r = Reader(data: data, offset: magic.count)
        let pointCount    = Int(try r.read(UInt32.self))
        let degreeRaw     = try r.read(UInt8.self)
        guard let shDeg   = SHDegree(rawValue: degreeRaw) else { throw CacheError.corrupted }
        let calibration   = try r.readFloat4x4()
        let locoPos       = try r.readFloat3()
        let locoSpan      = try r.read(Float.self)
        let modelPlacement = try r.readFloat4x4()
        let splatLen      = Int(try r.read(UInt64.self))
        let shLen         = Int(try r.read(UInt64.self))
        let splatData     = try r.readBytes(count: splatLen)
        let shData        = try r.readBytes(count: shLen)
        return CachedScene(calibration: calibration, locomotionPosition: locoPos,
                           locomotionSpan: locoSpan, modelPlacement: modelPlacement,
                           pointCount: pointCount, shDegree: shDeg,
                           splatData: splatData, shData: shData)
    }

    enum CacheError: Error { case badMagic, corrupted }

    // MARK: - Binary helpers

    private struct Writer {
        var data = Data()
        mutating func append(_ d: Data) { data.append(d) }
        mutating func write<T>(_ value: T) {
            withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
        }
        mutating func writeFloat3(_ v: SIMD3<Float>) {
            write(v.x); write(v.y); write(v.z)
        }
        mutating func writeFloat4x4(_ m: simd_float4x4) {
            for col in 0..<4 { write(m[col].x); write(m[col].y); write(m[col].z); write(m[col].w) }
        }
    }

    private struct Reader {
        let data: Data
        var offset: Int
        mutating func read<T>(_ type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { throw CacheError.corrupted }
            let v = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: type) }
            offset += size
            return v
        }
        mutating func readFloat3() throws -> SIMD3<Float> {
            SIMD3(try read(Float.self), try read(Float.self), try read(Float.self))
        }
        mutating func readFloat4x4() throws -> simd_float4x4 {
            let c0 = try SIMD4(read(Float.self), read(Float.self), read(Float.self), read(Float.self))
            let c1 = try SIMD4(read(Float.self), read(Float.self), read(Float.self), read(Float.self))
            let c2 = try SIMD4(read(Float.self), read(Float.self), read(Float.self), read(Float.self))
            let c3 = try SIMD4(read(Float.self), read(Float.self), read(Float.self), read(Float.self))
            return simd_float4x4(columns: (c0, c1, c2, c3))
        }
        mutating func readBytes(count: Int) throws -> Data {
            guard offset + count <= data.count else { throw CacheError.corrupted }
            let slice = data[offset..<(offset + count)]
            offset += count
            return Data(slice)
        }
    }
}

#endif

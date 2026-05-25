#if !os(visionOS)
import SwiftUI
import RealityKit
import UIKit

/// iOS/iPadOS：把 360° equirectangular 圖貼在大球體內壁，相機放球心，
/// 用拖曳手勢轉動視角 → 模擬「站在世界裡環視」。
/// （沒有 Vision Pro 也能驗證整套體驗。）
struct Immersive360View: View {
    let world: World

    @State private var committed = SIMD2<Float>(0, 0)   // 已固定的 yaw/pitch
    @State private var live = SIMD2<Float>(0, 0)        // 當前拖曳中的增量

    var body: some View {
        RealityView { content in
            // 球心相機
            let camera = PerspectiveCamera()
            camera.position = .zero
            content.add(camera)

            // 內壁貼圖的球體
            let sphere = await makeSkySphere(imageName: world.imageName)
            sphere.name = "sky"
            content.add(sphere)
        } update: { content in
            guard let sky = content.entities.first(where: { $0.name == "sky" }) else { return }
            let yaw = committed.x + live.x
            let pitch = committed.y + live.y
            sky.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    live = SIMD2(Float(value.translation.width) * 0.004,
                                 Float(value.translation.height) * 0.004)
                }
                .onEnded { _ in
                    committed += live
                    live = .zero
                }
        )
        .background(Color.black)
    }

    /// 建一個法線朝內、貼上 360° 圖的球體。
    private func makeSkySphere(imageName: String) async -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()

        if let cgImage = UIImage(named: imageName)?.cgImage,
           let texture = try? await TextureResource(
            image: cgImage,
            withName: imageName,
            options: .init(semantic: .color)
           ) {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            // 找不到圖的後備：純色，flow 一樣跑得起來
            material.color = .init(tint: .init(white: 0.25, alpha: 1))
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        // 翻面，讓貼圖顯示在球體內側
        entity.scale = SIMD3(-1, 1, 1)
        return entity
    }
}
#endif

#if os(visionOS)
import SwiftUI
import RealityKit

/// 6DoF spike (visionOS) — loads the resolved world's USDZ scene into an
/// `ImmersiveSpace(id: "world_3d")`. The user's head and body provide
/// real 6DoF tracking, so no virtual camera control is needed here.
///
/// Sibling to `ImmersiveWorldView` (which renders the 3DoF sphere skybox
/// inside `ImmersiveSpace(id: "world")`). Both spaces are registered in
/// `VisitingArtisanApp.swift` and exposed via separate buttons on the
/// `VisionWorldPanel` so the spike never blocks the main flow.
struct ImmersiveScene3DView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        RealityView { content in
            guard let world = appState.world else { return }
            let scene = await SceneLoader.loadScene(for: world)
            scene.name = "world_3d_scene"
            // The scene is placed at the world origin so the user is dropped
            // wherever the USDZ author intended. Some assets may need a
            // small floor offset; that's covered in the Day 3 review.
            content.add(scene)
        }
    }
}
#endif

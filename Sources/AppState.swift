import SwiftUI
import Observation
import UIKit

/// App 流程的階段。
enum AppPhase {
    case splash
    case quiz
    case loading
    case world
}

/// 全域狀態（quiz 答案、決定出來的世界、目前在哪一步）。
@Observable
final class AppState {
    var phase: AppPhase = .splash
    var answers = QuizAnswers()
    var world: World?

    /// Runtime panorama from World Labs (not a bundled asset). When set, the world
    /// views render this image instead of `world.imageName`.
    var generatedPano: UIImage?

    /// Remote (public CDN) `.spz` URL for the generated world's walkable 3D splat,
    /// plus its world id. Set when a World Labs world is generated; the world phase
    /// downloads the splat on demand when the user switches to "walkable".
    var generatedSplatURL: URL?
    var generatedWorldId: String?

    /// 隱藏連續分數（研究方向 6 底層）與映射出的世界參數（方向 7）。
    /// Phase 3 起算出並保存；Phase 2 起由顯示層消費 `worldParams`。
    var axisScores: AxisScores?
    var worldParams: WorldParams?

    /// quiz 答完 → 進 loading → 解析世界 → 進 world。
    func finishQuiz() {
        phase = .loading
        Task {
            // 模擬「生成世界」的過場（v2 這裡會是真的 API 呼叫）
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                // 研究方向 6→7：先算隱藏連續分數，再映射成世界參數。
                let scores = Scorer.score(self.answers)
                self.axisScores = scores
                self.worldParams = WorldMapper.map(scores)
                // title/blurb 從 archetype 衍生，確保 overlay 文字與 USDZ 場景一致。
                self.world = WorldCatalog.world(for: self.worldParams!.archetype)
                self.phase = .world
            }
        }
    }

    /// 重新開始。
    func restart() {
        answers = QuizAnswers()
        world = nil
        axisScores = nil
        worldParams = nil
        generatedPano = nil
        generatedSplatURL = nil
        generatedWorldId = nil
        phase = .splash
    }
}

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

    /// quiz 答完 → 進 loading → 解析世界 → 進 world。
    func finishQuiz() {
        phase = .loading
        Task {
            // 模擬「生成世界」的過場（v2 這裡會是真的 API 呼叫）
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                self.world = WorldCatalog.resolve(from: self.answers)
                self.phase = .world
            }
        }
    }

    /// 重新開始。
    func restart() {
        answers = QuizAnswers()
        world = nil
        generatedPano = nil
        phase = .splash
    }
}

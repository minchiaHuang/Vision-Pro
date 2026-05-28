import Foundation

/// 五題混合題型的作答結果。
/// energy/minutes 有預設值；need/help/week 需使用者選擇。
struct QuizAnswers {
    var energy: Double = 0.45      // Q1 slider: 0 = stillness, 1 = energy
    var need: String? = nil        // Q2 image grid: quiet/connection/movement/creativity
    var help: String? = nil        // Q3 icon grid: alone/talk/move/make
    var week: String? = nil        // Q4 image grid: exam/sleep/home/focus
    var minutes: Int = 10          // Q5 time row

    var isComplete: Bool { need != nil && help != nil && week != nil }
}

/// 單選題的一個選項。`image` 為對應的世界 asset 名（圖卡用），`symbol` 為 SF Symbol（icon 卡用）。
struct ChoiceOption: Identifiable, Hashable {
    let id: String
    let label: String
    var image: String? = nil
    var symbol: String? = nil
}

/// 一個生成（v1 為預先準備）的沉浸式世界。
struct World: Identifiable {
    let id: String
    let title: String          // 顯示在世界裡的一句話
    let imageName: String      // v1：打包進 Assets 的 360° 圖名稱（3DoF skybox）
    let imageURL: URL?         // v2：API 回傳的遠端圖
    let blurb: String          // 補充說明
    let narrationText: String  // Phase 1 旁白文字（30–50 字英文，現在式、感官語言）
    let sceneName: String?     // 6DoF spike：bundle 內的 USDZ 檔名（不含副檔名），nil 走 fallback

    init(
        id: String,
        title: String,
        imageName: String,
        imageURL: URL? = nil,
        blurb: String = "",
        narrationText: String = "",
        sceneName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.imageName = imageName
        self.imageURL = imageURL
        self.blurb = blurb
        self.narrationText = narrationText
        self.sceneName = sceneName
    }
}

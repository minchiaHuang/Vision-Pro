import Foundation

/// Quiz 的三個維度。
enum Dimension: String, CaseIterable, Identifiable {
    case emotional
    case cultural
    case physical
    var id: String { rawValue }

    var title: String {
        switch self {
        case .emotional: return "Emotional"
        case .cultural:  return "Cultural"
        case .physical:  return "Physical"
        }
    }
}

/// 一個 quiz 選項。`tag` 是用來組 prompt / 查表的關鍵字。
struct QuizOption: Identifiable, Hashable {
    let id: String
    let label: String
    let tag: String
}

/// 一道 quiz 題目。
struct QuizQuestion: Identifiable {
    let id: String
    let dimension: Dimension
    let prompt: String
    let options: [QuizOption]
}

/// 使用者答完後的結果：每個維度對應一個選到的 tag。
struct QuizResult {
    var answers: [Dimension: String] = [:]

    var isComplete: Bool {
        Dimension.allCases.allSatisfy { answers[$0] != nil }
    }

    func tag(for dimension: Dimension) -> String? {
        answers[dimension]
    }
}

/// 一個生成（v1 為預先準備）的沉浸式世界。
struct World: Identifiable {
    let id: String
    let title: String       // 顯示在世界裡的一句話
    let imageName: String   // v1：打包進 Assets 的 360° 圖名稱
    let imageURL: URL?      // v2：API 回傳的遠端圖
    let blurb: String       // 補充說明

    init(id: String, title: String, imageName: String, imageURL: URL? = nil, blurb: String = "") {
        self.id = id
        self.title = title
        self.imageName = imageName
        self.imageURL = imageURL
        self.blurb = blurb
    }
}

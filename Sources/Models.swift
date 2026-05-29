import Foundation

/// One this-or-that slider question (both poles are positive — no bad answer).
/// Left pole = score 0, right pole = score 1.
struct ThisOrThat: Identifiable {
    let id: String
    let question: String
    let leftLabel: String
    let rightLabel: String
}

/// Answers from the 4+1 axis quiz (research 方向 3).
struct QuizAnswers {
    /// 12 this-or-that slider values, 0...1 (0 = left pole, 1 = right pole).
    /// Index groups: [0-2] = axis1 自主↔歸屬, [3-5] = axis2 探索↔穩定,
    ///               [6-8] = axis3 表達↔連結, [9-11] = axis4 平靜↔生機.
    var sliders: [Double] = Array(repeating: 0.5, count: 12)
    /// Q14 hope direction — option id string ("ownPath" / "people" / "explore" / "stable").
    var hope: String? = nil
    /// Q15 free text — optional; used for world naming / atmosphere micro-tuning.
    var hopeFreeText: String = ""

    var isComplete: Bool { hope != nil }
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

// MARK: - Self-alignment scores (research 方向 6: the hidden continuous layer)

/// The direction the user wants to grow toward (research 軸5, non-bipolar).
/// Drives the world's distant focal point — never a good/bad score.
enum HopeDirection {
    case ownPath    // 更自在做自己
    case people     // 與人更靠近
    case explore    // 更敢去探索
    case stable     // 更踏實安定
}

/// The hidden bottom layer: where the user sits on each 4+1 axis.
/// Bipolar axes are 0...1 (0 = left pole, 1 = right pole — see comments).
/// Fed to `WorldMapper.map` to produce `WorldParams` (research 方向 7).
struct AxisScores {
    var autonomyBelonging: Double    // 軸1  0 = 自主, 1 = 歸屬
    var exploreStable: Double        // 軸2  0 = 探索, 1 = 穩定
    var expressionConnection: Double // 軸3  0 = 自我表達, 1 = 集體連結
    var calmVivid: Double            // 軸4 (state) 0 = 平靜, 1 = 生機
    var hope: HopeDirection          // 軸5  direction vector

    static let neutral = AxisScores(
        autonomyBelonging: 0.5, exploreStable: 0.5,
        expressionConnection: 0.5, calmVivid: 0.5, hope: .ownPath
    )
}

/// Coarse base world chosen from the structural axes. Research keeps a few
/// authored base structures and varies appearance continuously on top, rather
/// than a fixed preset per personality. Maps to a bundled USDZ.
enum WorldArchetype {
    case openNature     // 開闊自然  → Free_Low_Poly_Forest
    case cozyCommunal   // 內聚共處  → Cozy_living_room_baked
    case solitaryPath   // 獨處 / 路徑 → FREE_Dirt_Road_Through_Forest

    /// Bundled USDZ resource name (no extension). Matches `USDZDebug.models`.
    var usdzName: String {
        switch self {
        case .openNature:   return "Free_Low_Poly_Forest"
        case .cozyCommunal: return "Cozy_living_room_baked"
        case .solitaryPath: return "FREE_Dirt_Road_Through_Forest"
        }
    }
}

/// The middle layer: concrete, continuously-tunable parameters the display layer
/// applies on top of a base world (research 方向 7). Not discrete presets — two
/// users with the same archetype still differ because these values differ.
struct WorldParams {
    var archetype: WorldArchetype   // coarse base (軸2 / 軸3)
    var lightIntensity: Float       // 軸4 → DirectionalLight intensity
    var colorTemperature: Float     // 軸4 → Kelvin; calm = cooler, vivid = warmer
    var saturation: Double          // 軸4 → 0.5 (desaturated) … 1.1 (saturated)
    var socialDensity: Int          // 軸1 → ambient companions / lanterns to show
    var openness: Double            // 軸2 → 0 (enclosed refuge) … 1 (open prospect)
    var biophilicDensity: Double    // 軸3 → 0.3 (sparse personal) … 1 (lush shared)
    var focal: HopeDirection        // 軸5 → distant focal direction
}

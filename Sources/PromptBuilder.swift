import Foundation

/// 把 quiz 答案組成一段 text prompt。
/// v1：用來顯示「你的世界是根據這些生成的」+ 之後接 API（v2）直接餵給 Skybox AI。
enum PromptBuilder {

    /// 每個 tag 對應的視覺描述片段。
    private static let fragments: [String: String] = [
        // emotional
        "quiet":      "calm and serene",
        "connection": "warm and inviting",
        "movement":   "energetic and open",
        "creativity": "soft, imaginative light",
        // cultural
        "nature":     "natural landscape",
        "communal":   "warm communal space with a sense of gathering",
        "home":       "cozy familiar interior",
        "explore":    "expansive unfamiliar vista",
        // physical
        "still":      "still water, minimal motion",
        "active":     "dynamic terrain, sense of movement",
        "sensory":    "rich textures and gentle ambient detail",
        "rest":       "soft, restful atmosphere"
    ]

    static func prompt(from result: QuizResult) -> String {
        let parts = Dimension.allCases.compactMap { dim -> String? in
            guard let tag = result.tag(for: dim) else { return nil }
            return fragments[tag] ?? tag
        }
        let body = parts.joined(separator: ", ")
        return "An immersive 360 environment that feels \(body)."
    }
}

import Foundation

/// v1：預先準備好的世界 + 查表解析。
/// 之後 v2 會用 SkyboxService 即時生成取代 resolve()。
enum WorldCatalog {

    /// 打包進 Assets 的世界（imageName 要和 Assets.xcassets 裡的圖名一致）。
    static let all: [World] = [
        World(
            id: "calm_communal",
            title: "This is what balance feels like for you",
            imageName: "world_calm_communal",
            blurb: "A warm, communal space — calm but not empty."
        ),
        World(
            id: "open_nature",
            title: "This is what balance feels like for you",
            imageName: "world_open_nature",
            blurb: "Open nature — room to breathe and move."
        ),
        World(
            id: "quiet_solitary",
            title: "This is what balance feels like for you",
            imageName: "world_quiet_solitary",
            blurb: "A quiet, solitary place — nothing to prove."
        )
    ]

    /// 找不到對應圖時的後備（讓 flow 一定跑得起來）。
    static let fallback = World(
        id: "fallback",
        title: "This is what balance feels like for you",
        imageName: "world_calm_communal",
        blurb: "Your space."
    )

    /// 根據 quiz 結果查表決定世界。
    /// v1 邏輯刻意簡單：用 cultural + physical 的傾向決定大方向。
    static func resolve(from result: QuizResult) -> World {
        let cultural = result.tag(for: .cultural) ?? ""
        let physical = result.tag(for: .physical) ?? ""

        switch (cultural, physical) {
        case ("communal", _), ("home", _):
            return byId("calm_communal")
        case (_, "active"), ("explore", _), ("nature", _):
            return byId("open_nature")
        case (_, "still"), (_, "rest"):
            return byId("quiet_solitary")
        default:
            return fallback
        }
    }

    private static func byId(_ id: String) -> World {
        all.first { $0.id == id } ?? fallback
    }
}

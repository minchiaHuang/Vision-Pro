# Visiting Artisan — PRD

> Last aligned to code state: `dab3c9d` (feat/v2-foundation, 2026-05-28)
> Document version: v2 · AFP project + 個人 portfolio
> Apple Vision Pro app, iPad first

> This file is the **product thesis**. It deliberately does NOT duplicate code
> architecture or pipeline status:
> - For how things are built today, see [ARCHITECTURE.md](ARCHITECTURE.md)
> - For what's in flight and decision gates, see [ROADMAP.md](ROADMAP.md)
> - For asset coverage, see [WORLDS.md](WORLDS.md)

---

## 1. Vision

**一句話：** 一個透過「Who are you right now?」的短問答，幫大學生**感受**——而不只是理解——自己的平衡長什麼樣子。

| | |
|---|---|
| App 名稱 | Visiting Artisan |
| 平台 | Apple Vision Pro（沉浸主軸）+ iPad / iPhone（驗證 + 日常入口） |
| Challenge Statement | Helping individuals achieve balance through authentic self-alignment |
| App Statement | An app that helps university students understand who they are, by guiding them through a personalised quiz and immersing them in a world that reflects their authentic self. |
| 核心信念 | **Self-alignment = Balance.** 你無法對齊一個你不認識的自己，所以「理解你是誰」是「達成平衡」的前置必要條件。 |

**範圍界定（誠實標註）：** 這個產品做的是「**發現 + 體驗**」——第一面鏡子，讓抽象的平衡變成你站得進去、感受得到的東西。**日常維持**是後續方向，不在 3 週範圍。

---

## 2. Target User

**主要 persona：Aisha Mensah — "I Am What I Produce"**（成就驅動型，詳見 AFP day-05 筆記）

- 22 歲，大二 IT，UTS
- 把生產力 / 成就等同於整體健康；除了「高成就學生」之外不知道自己是誰
- 會跳過任何像「自我反思」的工具
- **進入點（Hook）：** 不是 wellness、是科技新鮮感——「2 分鐘 quiz 生成你專屬的 Vision Pro 世界」對她是好玩、低承諾、可炫的東西。wellness gap 在她進來後才被動浮現。

> Aisha persona 沿用 v1。即使 quiz 設計後續可能改（見 §4），這個使用者描述不變。

---

## 3. Core User Flow

```
Splash（App 名稱 + Begin）
    ↓
五題 soft questions（energy slider · need · help · week shape · time）
    ↓
"Weaving..." 過場（~2 秒）
    ↓
你的沉浸式世界（4 種之一）
    ├─ 預設：3DoF 360° 環視 skybox
    └─ 實驗入口：「View in 6DoF (spike)」按鈕進可走動 USDZ 場景
    ↓
"Start over" 回 Splash
```

對應 user stories（保留 v1）：

1. As a user, I want to answer a "Who are you?" quiz so that I can get my own personalised immersive world.
2. As a user, I want to step into my generated world so that I can *feel* — not just understand — what my balance looks like.
3. As a user, I want to return to my space so that I can rebalance in daily life.

> Flow 圖跟 v1 同樣的精神（quiz → world），差別是 quiz 從「3 維度」變成「5 soft questions」，World 多了 6DoF 實驗入口。詳細狀態見 [ARCHITECTURE.md](ARCHITECTURE.md) §4。

---

## 4. Quiz Design — Research Gap ⚠️

**這一節從產品 spec 降級成「公開的未決問題」。**

### 現況（code 真相）

[`QuizData.swift`](Sources/QuizData.swift) + [`Models.swift`](Sources/Models.swift) `QuizAnswers` 目前用的是 5 題格式：

| Q | 類型 | 變數 | 選項 |
|---|---|---|---|
| 1 | Slider | `energy: Double (0–1)` | stillness ↔ bright energy |
| 2 | Image grid | `need: String?` | quiet / connection / movement / creativity |
| 3 | Icon grid | `help: String?` | alone / talk / move / make |
| 4 | Image grid | `week: String?` | exam / sleep / home / focus |
| 5 | Time row | `minutes: Int` | 5 / 10 / 15 / 20 / 30 |

對應的 mapping 邏輯在 [`WorldCatalog.swift`](Sources/WorldCatalog.swift) `resolve()`：四個世界（`starry_night / open_nature / warm_communal / quiet_solitary`）按條件分配。詳見 [ARCHITECTURE.md](ARCHITECTURE.md) §6。

### v1 原本的設計（保留供對照）

PRD v1 寫的是 **3 個維度**，每個維度 1–2 題：

| 維度 | 問題（v1 draft） | 影響世界的什麼 |
|---|---|---|
| **Emotional** | When you feel off-balance, what do you need most? | 氛圍、光線、色溫 |
| **Cultural** | Where do you feel most like yourself? | 場景元素、共處 vs 獨處空間、文化符號 |
| **Physical** | How does your body recharge? | 地景型態：開闊動態 vs 靜謐留白 |

差異化關鍵在 **Cultural 維度**——集體 / 家庭導向 vs 個人 / 獨立導向。對照西方中心競品（TRIPP 等），別人的「平衡」預設是空靈海灘；對集體文化背景的人，平衡可能是熱鬧的家庭廚房。

### 為什麼是 Research Gap

- code 已落地的 5 題與 v1 的 3 維度**沒有對應關係**——`energy / need / help / week / minutes` 不能直接對映 Emotional / Cultural / Physical
- 特別是**文化維度暫時沒進 quiz**——只間接由「warm_communal vs quiet_solitary」這兩個世界的存在暗示
- 小組還沒重新對齊「quiz 該問什麼」這件事

### 當下立場

- **產品焦點優先放在 3D 世界的呈現**（3DoF skybox 主線 + 6DoF spike），quiz 設計排隊
- **不改動 code** — 5 題 quiz 保留，現有 mapping 繼續用
- **Target resolution: Week 1.5**（在小組 sync 時 reconverge）

**可能的決議方向（不預先選邊）：**

1. 承認 5 題就是定稿，把 Emotional / Cultural / Physical 概念退場
2. 在 5 題之上補 1–2 題 cultural 題（混合方案）
3. 重做 quiz，回到 3 維度結構（最大改動）

選哪個取決於：(a) 6DoF spike 結果（影響整體開發時間預算）、(b) AFP 評審對「文化差異化」的反饋。

---

## 5. Technical Architecture

→ 完整描述見 [ARCHITECTURE.md](ARCHITECTURE.md)。

**摘要：** 單 Xcode target、多平台（iOS + iPadOS + visionOS）、共用 SwiftUI core。三條 world rendering pipeline 並陳：

| Pipeline | 狀態 | 主檔 |
|---|---|---|
| 3DoF skybox（主線） | 🟢 working | `Immersive360View` / `ImmersiveWorldView` |
| 6DoF USDZ spike | 🟡 in progress（Day 1 of 3） | `Scene3DView` / `SceneLoader` |
| WorldLabs API spike | 🔴 inert without key | `WorldLabsService` / `WorldLabsTestView` |

---

## 6. Pipeline & Decisions

→ 完整 timeline + decision gates 見 [ROADMAP.md](ROADMAP.md)。

**摘要：**

- 主線是 3DoF skybox + 預先準備好的 equirectangular panorama，跟 v1 路線一致
- 並行 6DoF spike，用 3 天驗證 USDZ 可走動世界值不值得 commit
- WorldLabs API 是更早的 feasibility spike，**留在 build target 但未整合進 quiz flow**，給未來 v2 評估用
- World Labs Marble walkable / Skybox AI live generation / Google Genie 3 / SIMA 2 都**不在 3 週範圍**——理由與評估記錄在 [ROADMAP.md](ROADMAP.md)

---

## 7. Phasing

→ 不再用 v1/v2/v3/v4 階段表（PRD v1 的形式），改用 [ROADMAP.md](ROADMAP.md) 的「pipeline 狀態 + 決策 gate」模型。

**為什麼換寫法：** v1/v2/v3/v4 暗示線性升級路線。實際情況是**三條 pipeline 並存**，下一步取決於 spike 結果而不是預先排定的版本號。

---

## 8. Data Model

```swift
struct QuizAnswers {
    var energy: Double = 0.45          // Q1 slider
    var need: String? = nil            // Q2 image grid
    var help: String? = nil            // Q3 icon grid
    var week: String? = nil            // Q4 image grid
    var minutes: Int = 10              // Q5 time row
    var isComplete: Bool { ... }
}

struct ChoiceOption: Identifiable, Hashable {
    let id: String
    let label: String
    var image: String? = nil           // image-grid 卡用
    var symbol: String? = nil          // SF Symbol（icon-grid 卡用）
}

struct World: Identifiable {
    let id: String
    let title: String
    let imageName: String              // Assets.xcassets 內的 3DoF 360° 圖
    let imageURL: URL?                 // v2：API 回傳的遠端圖（dormant）
    let blurb: String
    let narrationText: String          // Phase 1 旁白（dormant，等 voice-over 系統）
    let sceneName: String?             // 6DoF spike：USDZ 檔名（nil 走 fallback）
}
```

`narrationText` 跟 `sceneName` 都已在 model 加好但**現在還沒被任何主流程讀取**——它們是給未來功能（voice-over、6DoF）的擴充點。

---

## 9. Research Gaps（誠實列出）

按優先序：

1. **Quiz dimension design**（最大缺口）—— 見 §4。5 題 vs 3 維度的取捨還沒做。Target resolution: Week 1.5 小組 sync。
2. **答案 → 世界的 mapping 是否真的 personalised** —— 目前 `WorldCatalog.resolve()` 的優先序是工程直覺，沒有使用者測試。需要 3–5 人實測「進到的世界感覺像我嗎」。
3. **Cultural 維度的呈現** —— 即使 quiz 不問 cultural 題，世界本身可不可以視覺上承載這個差異？warm_communal vs quiet_solitary 的對比夠不夠？
4. **Aisha 進入後的 gap surfacing** —— 她是被「科技新鮮感」勾進來的（不是 wellness），進來後 app 怎麼被動讓她看見「你以為的自己 vs 生成的世界」之間的落差？
5. **6DoF 可行性** —— 進行中。spike Day 3 review 後更新 [ROADMAP.md](ROADMAP.md)。
6. **「achieve」的延伸** —— daily 入口、rebalance 機制，3 週範圍之外。

---

## 10. Out of Scope（3 週內）

| 項目 | 為什麼不做 |
|---|---|
| World Labs Marble walkable（Gaussian splats） | 顯示管線需要 MetalSplatter + 自寫 shader，估 3–6 週。6DoF USDZ spike 是輕量替代。 |
| Skybox AI 即時生成 | API tier 是 Business $112/mo，3 週預算不合理。手動生圖無架構投資回報。 |
| 雙向 AI 對話（SFSpeechRecognizer + LLM + TTS） | Phase 2 stretch，等 3 週 ship 後。 |
| Daily 回訪 / rebalance 機制 | 屬「日常維持」範疇，不在「發現 + 體驗」這一面鏡子內。 |
| 多人 / 社群 | 不在 v1–v3 範疇。 |

---

## 11. Success Criteria（3 週交付）

- ✅ Clean clone 可在 iPad Pro 13" (M5) + Apple Vision Pro 模擬器上 build & run（[`bin/verify.sh`](bin/verify.sh) 兩個都 PASS）
- ✅ Quiz 5 題跑得通，answer 結束會解析到 4 個世界之一
- ⏳ 4 個世界都有可看的內容（**目前 2 / 4 有 3DoF skybox、2 / 4 有 6DoF USDZ**——見 [WORLDS.md](WORLDS.md)）
- ⏳ Vision Pro 真機跑得起來，沉浸感成立
- ⏳ 至少能錄一段 90 秒 demo 影片給 AFP

---

## 12. Document History

| 版本 | 日期 | 變更 |
|---|---|---|
| v0.1 | 2026-05-25 | Initial PRD（3 維度 quiz、v1/v2/v3/v4 階段表、Marble v4 stretch） |
| **v2** | 2026-05-28 | **本檔**。Thesis + Aisha 保留；quiz 改成 Research Gap；Phasing 改成指向 ROADMAP；資料模型加 `sceneName` + `narrationText`；新增 §10 Out of Scope、§11 Success Criteria |

v0.1 內容可從 git 歷史取得：`git show 67cf424:PRD.md`。

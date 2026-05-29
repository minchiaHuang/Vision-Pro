# Visiting Artisan — PRD & Technical Architecture

> Apple Vision Pro app　|　AFP project + 個人 portfolio
> 文件版本：v0.1（2026-05-25）

---

## 1. Product Overview

**一句話：** 一個透過「Who are you?」quiz 生成你專屬沉浸式世界的 app，讓大學生*感受*——而不只是理解——自己的平衡長什麼樣子。

| | |
|---|---|
| **App 名稱** | Visiting Artisan |
| **平台** | Apple Vision Pro（主）＋ iPad/iPhone（驗證 + 日常入口） |
| **Challenge Statement** | Helping individuals achieve balance through authentic self-alignment |
| **App Statement** | An app that helps university students understand who they are, by guiding them through a personalised quiz and immersing themselves in a world that they describe, letting them feel what their authentic self feels like. |
| **核心信念** | Self-alignment = Balance。你無法對齊一個你不認識的自己，所以「理解你是誰」是「達成平衡」的前置必要條件。 |

**範圍界定（誠實標註）：** 這個產品做的是「**發現 + 體驗**」——第一面鏡子，讓抽象的平衡變成你站得進去、感受得到的東西。**日常維持**是後續方向，不在 v1–v3 範疇。

---

## 2. Target User

**主要 persona：Aisha Mensah — "I Am What I Produce"**（成就驅動型，詳見 AFP day-05 筆記）

- 22 歲，大二 IT，UTS
- 把生產力/成就等同於整體健康；除了「高成就學生」之外不知道自己是誰
- 會跳過任何像「自我反思」的工具
- **進入點（Hook）：** 不是 wellness、是科技新鮮感——「2 分鐘 quiz 生成你專屬的 Vision Pro 世界」對她是好玩、低承諾、可炫的東西。wellness gap 在她進來後才被動浮現。

---

## 3. Core User Flow

```
Splash（App 名稱）
    ↓
"Who are you?" Quiz（3 維度，每維度 1–2 題）
    ↓
"Building your world…"（過場 / loading）
    ↓
你的沉浸式世界（可走動 3D）
    ↓
與 AI 語音陪伴對話（v4：先 speech-to-chat，後續深化為「引導反思」的導師）
    ↓
（後續）daily 入口：回到你的空間
```

對應 user stories：
1. As a user, I want to answer a "Who are you?" quiz so that I can get my own personalised immersive world.
2. As a user, I want to step into my generated world so that I can *feel* — not just understand — what my balance looks like.
3. As a user, I want to return to my space so that I can rebalance in daily life.

---

## 4. Quiz Design

> ⚠️ **這一塊需要更多 research**（見 §9）。以下是 working draft，不是定稿。

3 個維度，每個維度的答案會映射成生成世界的視覺參數：

| 維度 | 問題（draft） | 選項 | 影響世界的什麼 |
|---|---|---|---|
| **Emotional** | When you feel off-balance, what do you need most? | Quiet alone / Talk to someone / Move your body / Create something | 氛圍、光線、色溫 |
| **Cultural** | Where do you feel most like yourself? | In nature / Around people / At home / Somewhere new | 場景元素：共處空間 vs 獨處空間、文化符號 |
| **Physical** | How does your body recharge? | Stillness / Movement / Sensory calm / Rest | 地景型態：開闊動態 vs 靜謐留白 |

**Cultural 維度的機制（差異化關鍵）：**
- 集體/家庭導向 → 溫暖共處空間、聚會場景、熟悉文化符號（不是空無一人）
- 個人/獨立導向 → 開闊獨處空間、安靜、留白
- vs 西方中心競品（TRIPP 等）：別人的「平衡」預設是空靈海灘；對集體文化背景的人，平衡可能是熱鬧的家庭廚房。

---

## 5. Technical Architecture

**策略：一個 Xcode 專案，兩個 target，共用核心邏輯。**

```
┌─ Shared（iPad + visionOS 共用，純 Swift，無 UI 依賴）──┐
│  Models/                                               │
│    QuizQuestion, QuizAnswer, QuizResult                │
│    World (id, title, imageName/imageURL, description)  │
│  Logic/                                                │
│    PromptBuilder   : QuizResult → text prompt          │
│    WorldResolver   : QuizResult → World（v1 查表）      │
│    SkyboxService   : prompt → 360° image（v2 才接 API） │
└─────────────────────────────────────────────────────────┘
            ↓ 顯示層分平台
  iOS/iPadOS target:
    QuizView (SwiftUI) → WorldView
    360 viewer：RealityKit 球體 mesh，內側貼 equirectangular 圖
    觸控拖曳 / CoreMotion 陀螺儀環視
  visionOS target:
    QuizView (SwiftUI，windowed)
    ImmersiveSpace：球體 skybox，真沉浸
```

**為什麼這樣分：**
- Quiz UI 和邏輯兩平台 100% 共用（SwiftUI + 純 Swift model）
- 只有「世界怎麼顯示」分平台：iPad 是可環視的 360°（驗證用），visionOS 是真沉浸
- 沒有 Vision Pro 在手時，iPad/模擬器就能跑完整套流程

**360° 顯示原理（兩平台共通）：**
- 建一個大球體 mesh，法線翻向內側
- 把 equirectangular（2:1）360° 圖當材質貼在球體內壁
- 相機放在球心 → 看出去就是環繞環境
- visionOS 用 `ImmersiveSpace` + RealityKit；iPad 用 `RealityView` 或 SceneKit，相機隨手勢/陀螺儀轉

---

## 6. End-to-End Pipeline（「整套能不能跑」）

```
Quiz 答案（QuizResult）
    ↓ PromptBuilder
text prompt
  例："calm, warm communal interior, soft light, gathering space"
    ↓
  v1: WorldResolver 查表 → 對應一張預先生成的打包圖   ← 不需網路/API
  v2: SkyboxService → Skybox AI REST API → 即時 360° 圖 ← 需 API key
    ↓
World(image)
    ↓ 顯示層
  iPad：球體 360° 環視
  visionOS：ImmersiveSpace 真沉浸
```

**v1 完全本地、零外部依賴就能跑完整套**——這就是「先了解整套下來能不能跑」的答案：能。

> **顯示層 note：** v1/v2 的 `SkyboxService` 對應 **Skybox AI API**（360° equirectangular → 球體貼圖），
> 現有 `Immersive360View` / `ImmersiveWorldView` 直接吃這種圖。
> v5 改用 Marble 時，顯示層要從「球體貼圖」換成「splat / mesh 場景」——是**另一條顯示管線**（見 §6.5 決策）。

---

## 6.5 World Generation Backend — 決策

> 世界生成靠外部產品。市面分兩類，差別決定整個顯示管線與工程難度。已查證 2026 最新狀態。

| 類型 | 代表 | 體驗 | 進 Vision Pro |
|---|---|---|---|
| **360° skybox** | **Skybox AI**（Blockade Labs） | 站著環視、被包圍（不能走動） | ✅ 簡單：球體內壁貼 equirectangular 圖 |
| **可走動 3D 世界** | **World Labs Marble** | 6DOF 走動探索 | ⚠️ 重：Gaussian splat / mesh 渲染 |

### ✅ 決策：v1–v3 用 Skybox AI；v4 stretch 升級 Marble

**為什麼 Skybox AI 先行：**
- 完全匹配現有架構（球體 skybox），程式碼零重寫
- 官方有 visionOS / Vision Pro spatial 專屬支援
- 情感目標（被你的世界包圍、感受平衡）360° 環視已足夠沉浸
- 學生可行 + 便宜；符合「without AI unless needed」（v1 預生圖）

### 查證事實（2026）

| 產品 | 重點 |
|---|---|
| **Skybox AI** | equirectangular 最高 8K（Business 16K）；官方 visionOS/Vision Pro spatial 支援頁；**API 在 Business $112/mo**；手動生圖 Essential $20/mo 或免費試 |
| **World Labs Marble** | text/image/video → 可走動 3D 世界；匯出 Gaussian splat(PLY)/mesh(GLB)/video；有 **World API**；可在 Vision Pro 原生觀看；PLY→USDZ 需 NVIDIA Omniverse NuRec |
| **中間方案** | visionOS 26 Photos 內建一鍵 **Spatial Scene**（Apple 開源 on-device gaussian splatting, SHARP）——單圖 → 體積場景，可當輕量探索路線 |

> 💰 **成本提醒：** Skybox **API 僅 Business $112/mo**。所以 v1/v2 盡量用**手動生圖 / Essential tier**，
> 真的需要「quiz → 即時生成」才接 API，避免太早燒預算。

來源：
- [Skybox AI for Spatial Applications（Vision Pro/XR）](https://www.blockadelabs.com/industries/skybox-ai-for-spatial-applications)
- [Skybox API 文件](https://api-documentation.blockadelabs.com/api/skybox.html)
- [World Labs — Marble World Model](https://www.worldlabs.ai/blog/marble-world-model)
- [Marble Mesh Export 文件](https://docs.worldlabs.ai/marble/export/mesh)
- [MetalSplatter（visionOS splat 渲染，開源）](https://github.com/scier/MetalSplatter)

---

## 7. 分階段（Phasing）

> **方向調整：** v1（整套 flow 跑得通，預生 360° 查表）已完成；原本 v2 的「Skybox AI 即時生成 360°」
> **跳過不做**——直接跳到「可走動的世界」這條路。以下從目前所在的 **v3** 起算。

| 階段 | 目標 | 顯示 | 世界來源 | 外部申請 | 狀態 |
|---|---|---|---|---|---|
| **v3** | 可走動的 3D 世界 | Vision Pro / iPad，6DOF 走動探索 | 預先做好的 USDZ mesh 場景 | ❌ 無（本地 USDZ） | 🔵 進行中（USDZ mesh + PS5 手把 spike） |
| **v4** | **AI 語音對話**（世界裡的陪伴／導師） | 世界內語音互動 | — | 對話 LLM（on-device 或 API） | 🔵 6a 進場敘事 ✅（內建 `AVSpeechSynthesizer` TTS，零權限；`NarrationService` + `NarrationComposer`）；6b 雙向 speech-to-chat（mic→STT→雲端 LLM→TTS）⬜ 待核准套件/金鑰；「AI 導師引導反思」人設／提問設計留到 §9 research 後深化 |
| **v5** | 可走動 **+ AI 即時生成**的世界 | 同上 | World Labs Marble（World API → splat / mesh） | Marble API + splat/mesh 渲染整合 | ⬜ 未開始（原 v4） |
| **v6** | Vision Pro 實機部署 | Vision Pro 實機 | 同 v5 | Apple Developer（免費 tier 跑自己裝置） | ⬜ 最後（原 v5） |

> **v4 分兩段**：先做 **6a 進場敘事**（進世界時嚮導用 quiz 分數＋原型「介紹你的世界」，純內建 TTS，零金鑰/零權限，iPad 模擬器可驗）✅；再做 **6b 雙向 speech-to-chat（麥克風→STT→雲端 LLM→TTS）**，維持 spike 性質、需先核准套件/金鑰；上真機感受延遲後再決定是否正式投入，不在頭顯驗證前承諾做完整。
> v5 把「預先做好的可走動場景」升級成「AI 即時生成的可走動世界」（顯示層維持 splat/mesh 管線）。v6 把成品部署上 Vision Pro 實機。

---

## 8. Data Model（v1）

```swift
struct QuizQuestion: Identifiable {
    let id: String
    let dimension: Dimension   // .emotional / .cultural / .physical
    let prompt: String
    let options: [QuizOption]
}

struct QuizOption: Identifiable {
    let id: String
    let label: String
    let tag: String            // 用來組 prompt / 查表的關鍵字
}

struct QuizResult {
    var answers: [Dimension: String]   // dimension → 選到的 tag
}

struct World: Identifiable {
    let id: String
    let title: String          // e.g. "This is what balance feels like for you"
    let imageName: String      // v1：打包進 app 的 asset 名
    let imageURL: URL?         // v2：API 回傳
    let blurb: String
}
```

---

## 9. 還需要的 Research（誠實列出缺口）

> 這些是 v1 之後要補的，不影響 v1 跑起來，但影響產品說服力。

1. **個性化問題設計** — 目前 quiz 題目是 working draft。需要 research：
   - 哪些問題真的能問出「self-alignment / authentic self」，而不只是偏好？
   - 文化維度怎麼問才不淺薄、不刻板印象？
   - 幾題才夠（太少不準，太多 Aisha 會跳出）？
2. **答案 → 世界的 mapping** — 什麼樣的視覺真的讓人感覺「對齊自己」？需要使用者測試。
3. **Aisha 進入後的 gap surfacing** — 她進來後，app 怎麼被動讓她看見「你以為的自己 vs 生成的世界」之間的落差？
4. **「achieve」的延伸** — daily 入口、rebalance 機制（v3+ 範疇）。
5. **v5 Marble 可行性** — quiz → Marble prompt 的個人化成本/延遲、Gaussian splat 在 Vision Pro 的渲染效能，都需要實測才能確認 v5 值不值得做。
6. **AI 語音陪伴/導師（v4）** — 它該問什麼才真的扣到 self-alignment（而非閒聊）？人設與語氣？多輪對話怎麼收尾？語音延遲與自然度在頭顯裡感受如何（只能上真機判斷）？語音資料隱私、on-device vs 雲端取捨。

---

## 10. Tech Stack

| 項目 | 選擇 |
|---|---|
| 語言 | Swift |
| UI | SwiftUI |
| 3D / 360° | RealityKit（球體 skybox） |
| 沉浸 | visionOS `ImmersiveSpace` |
| iPad 環視 | `RealityView` + CoreMotion / 手勢 |
| 網路（v2） | URLSession → Skybox AI REST API |
| 生圖（v2） | Skybox AI（Blockade Labs），text → 8K 360° equirectangular |
| 生世界（v5） | World Labs Marble（World API）→ Gaussian splat / mesh |
| splat 渲染（v5） | MetalSplatter（開源）或 mesh(GLB) 匯入 RealityKit；或 PLY→USDZ via Omniverse NuRec |
| 輕量中間方案 | visionOS 26 內建 Spatial Scene（單圖 → 體積場景） |
| 語音輸入 STT（v4） | Speech framework / iOS 26 SpeechAnalyzer |
| 語音輸出 TTS（v4） | AVSpeechSynthesizer（或更自然的第三方／雲端 TTS） |
| 對話 AI（v4） | LLM——on-device Foundation Models 或雲端 API |
| 空間音訊（v4，visionOS） | RealityKit spatial audio，讓陪伴的聲音定位在世界裡 |
| IDE | Xcode 26.5 |

---

## 11. v1 Definition of Done

- [ ] App 啟動 → Splash → Quiz（3 維度）
- [ ] 答完 quiz → loading 過場
- [ ] 根據答案查表 → 顯示對應的預先生成 360° 世界
- [ ] iPad：可拖曳/陀螺儀環視整個世界
- [ ] visionOS 模擬器：ImmersiveSpace 沉浸顯示
- [ ] 至少 3 種答案組合 → 3 個明顯不同的世界（讓人感受到「個人化」）

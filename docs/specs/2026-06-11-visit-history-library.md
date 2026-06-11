# Spec — Visit History Library(回到舊世界 · 本地存檔)

| | |
|---|---|
| 狀態 | 已核准,待實作 |
| 日期 | 2026-06-11(AEST) |
| 範圍 | Future Museum(Oops 流程)· **每次世界 6 張圖** |
| 實作分支 | `feat/visit-history-library` |

---

## Context(為什麼做這個)

目前 App 沒有任何持久化,使用者「生成的世界」(策展人故事 + 牆上的畫 + 答案)只活在記憶體 `AppState`,一旦 `restart()` 或關 App 就消失,**無法回到去過的地方**。

Home 上已有 `Visit Old World` 按鈕,但它是「假的」:`OopsFlow.enterWorld()`(`Sources/Oops/OopsFlow.swift:148`)只帶入「當下記憶體裡」的 `museumStory`,沒有就 fallback 到寫死的 `BeatPlaqueSample` 範例。

目標:像遊戲存檔一樣,使用者去過的世界在**本地**留下記錄(標題 + 預覽縮圖 + 日期),之後可從格子畫面點回去重新進入 —— **不重打 AI、不需要 database、不裝任何套件**。

---

## 已鎖定的決定

| 項目 | 決定 |
|---|---|
| 範圍 | 只做 Future Museum(Oops 流程);不含 splat / 360 全景 |
| 每次世界圖數 | **6 張**(`story.nodes` 全部,beat 順序) |
| 存檔時機 | **進場即存**(無圖的 shell,卡片立刻出現)→ 6 張生成完(`.ready`)再就地補圖/縮圖 |
| 卡片標題 | 使用者想成為的角色(`museumAnswers.role`)+ 建立日期 |
| 預覽縮圖 | 最後一張 beat(elixir / `tone == "warm"` / 成果那幕) |
| 空狀態 | 沒存檔時只顯示空狀態提示(不保留 Demo 卡) |
| 持久化 | UserDefaults 存索引 + `Documents/Visits/<id>/` 存圖,照抄 `SplatLibrary` 範式 |

---

## 關鍵技術發現:還原 = 只塞回 3 個欄位(低風險)

追過牆面貼圖的兩條路徑(`Sources/World/ImmersiveWorldView.swift:41-126`):

- **初始建構**:`ParametricWorldBuilder.build(params:, galleryPhotos: appState.galleryImages)` → 牆面初始貼圖讀**靜態** `galleryImages`。
- **即時串流**:`GalleryWallStreamer.applyIfNeeded(generator:)` 讀 `museumGenerator.nodes`,但 generator 為空時 `signature == appliedSignature` 直接 return → **自動 no-op**,不會洗掉 build-time 貼圖。
- **解說牌**讀 `appState.museumStory?.nodes`;**策展人語音**由 `enterWorld()` 用 `museumStory` 設定。
- **Developing/Failed 遮罩**是 `ForEach(appState.museumGenerator.nodes)`,generator 為空 → 不會出現。

**結論:** 還原一個舊世界,只要設好 `museumStory`、`museumAnswers`、`galleryImages` 三個欄位、保持 `museumGenerator` 為空,再呼叫現有 `enterWorld()`,世界渲染那一整層(牆、locomotion、解說牌、語音)完全沿用、不重打 AI。風險集中在「序列化存/讀 + 一個格子畫面」。

---

## 設計

### 1. 資料模型(新檔 `Sources/Museum/VisitRecord.swift`)

```swift
/// 一次已完成的 Future Museum 造訪,本地持久化。
struct VisitRecord: Codable, Identifiable {
    let id: String            // UUID
    let title: String         // = museumAnswers.role(空則 fallback,見 Edge cases)
    let createdAt: Date       // 卡片副標日期
    let story: MuseumStory     // 已是 Codable,直接存(含 6 個 node 的 caption/narration/tone…)
    let answers: MuseumAnswers // 見下:替 MuseumAnswers 加 Codable
    let imageFiles: [String]   // 6 張畫的相對檔名,beat 順序(對齊 story.nodes)
    let heroThumb: String      // 卡片預覽縮圖檔名(= elixir 那張的縮圖)

    /// 還原時用:Documents/Visits/<id>/ 下各檔的絕對路徑。
    func imageDir() -> URL     // FileManager .documentDirectory / "Visits" / id
}
```

- `MuseumStory` / `MuseumNode` 已是 `Codable`(`Sources/Museum/MuseumModels.swift:40-60`),直接存。
- `MuseumAnswers`(`Sources/Museum/MuseumModels.swift:15`)目前**非 Codable**,但欄位全是 String/Int(`promptInput` 是 computed,Codable 會忽略)→ 只要加 `: Codable` 即可,不另建型別。

### 2. 儲存層(同檔 `VisitLibrary`)—— 照抄 `SplatLibrary`

範式來源:`Sources/Spikes/SplatLibraryView.swift:34-65`。

```swift
enum VisitLibrary {
    static let storageKey = "visit.library.v1"   // UserDefaults 只存「索引」(metadata 陣列)
    static func load() -> [VisitRecord]
    static func add(_ record: VisitRecord)        // 插到最前、以 id 去重(newest wins)
    static func remove(id: String)                // 同時刪 Documents/Visits/<id>/ 整個資料夾
    // private save(_:) → UserDefaults.set(JSONEncoder().encode(records))
}
```

- **影像不進 UserDefaults**(太大):6 張原圖 + 1 張縮圖寫到 `Documents/Visits/<id>/`。
  - 原圖:`beat-0.jpg … beat-5.jpg`,JPEG 0.9(gpt-image base64 PNG 約 1MB/張,6 張 JPEG 後約 3–4MB)。
  - 縮圖:`thumb.jpg`,最後一張(elixir)縮到 512px、JPEG 0.8。
- UserDefaults 只放 `VisitRecord` 的 metadata(含檔名清單),啟動時 `load()` 解碼即可列表;進世界時才從磁碟 decode 原圖。

### 3. 存檔時機(進場即存,圖再補)

> 改版原因(2026-06-11 實測):原本「等 `.ready` 才存」需約 90s,使用者回 library 看得太早 → 看不到卡。改成**進場即存 shell**。

- **掛在長壽命的 `AppState`**,不是會被拆掉的 `GeneratingScreen`(進世界會 dismiss dev-menu window → 拆掉 GeneratingScreen)。
- 做法:`GeneratingScreen.runGeneration()`(`Sources/Oops/OopsWorldScreens.swift:77`)進世界後呼叫 `appState.saveCurrentVisit()`,兩段:
  ```swift
  // 立即:卡片馬上存在(無圖的 shell)
  guard let story = museumGenerator.story, let answers = museumAnswers else { return }
  let id = UUID().uuidString
  VisitLibrary.add(VisitLibrary.makeShell(id: id, story: story, answers: answers))
  // 延遲:6 張畫好(.ready)後就地補圖 + 縮圖到同一筆(同 id/title/createdAt)
  Task { @MainActor in
      await museumGenerator.waitUntilReady()
      guard museumGenerator.story?.persona == story.persona,
            museumGenerator.nodes.count == story.nodes.count else { return }   // 同一輪保護
      let imageData = museumGenerator.nodes.map { $0.image }
      await Task.detached { VisitLibrary.fillImages(id: id, imageData: imageData) }.value
  }
  ```
- `MuseumGenerator` 需新增 `func waitUntilReady() async { await paintTask?.value }`(目前 `paintTask` 私有)。
- **同一輪保護**:90s 內若重生成,`reset()` 會換掉 story/nodes;persona + nodes.count 比對不符就跳過補圖,避免第二輪的圖落進第一筆。
- **個別失敗容忍**:`.ready` 仍會觸發即使某張圖 `failed`;失敗的格子寫空檔名,其餘照存。

### 4. 還原路徑(`AppState.loadSavedVisit(_:)`)

```swift
func loadSavedVisit(_ record: VisitRecord) {
    museumGenerator.reset()                    // 保持空,讓 streamer no-op、不出 Developing 遮罩
    museumStory   = record.story
    museumAnswers = record.answers
    galleryImages = record.loadImages()        // 從磁碟 decode 成 [UIImage],缺檔補 placeholder
}
```

之後沿用現有 `OopsFlow.enterWorld()` 完全不改(它會用 `museumStory` 設定策展人語音、開 BA396 immersive space)。

### 5. 瀏覽 UI(新檔 `Sources/Oops/OopsLibraryScreen.swift`)

- 新增 `OopsScreen.library` case(`Sources/Oops/OopsFlow.swift:6` enum)。
- `HomeScreen` 的 `Visit Old World`(`Sources/Oops/OopsOnboarding.swift:237`)由 `onVisitOld: { enterWorld() }` 改成 `onVisitOld: { go(.library) }`。
- `OopsLibraryScreen`:沿用 Oops 玻璃語言(`OopsGlass` / `oopsCard`),遊戲存檔式 grid 卡片 = elixir 縮圖 + 角色標題 + 日期;含 back 回 home、刪除(對應 `VisitLibrary.remove`)。
- 點卡片 → `appState.loadSavedVisit(record)` → 觸發 `enterWorld()`(沿用 `OopsFlowView` 既有路徑)。
- **空狀態**:沒存檔 → 只顯示「還沒有去過的世界」提示(無 Demo 卡)。

---

## 要改 / 新增的檔案

| 動作 | 檔案 | 內容 |
|---|---|---|
| 新增 | `Sources/Museum/VisitRecord.swift` | `VisitRecord` 模型 + `VisitLibrary` 儲存層 |
| 新增 | `Sources/Oops/OopsLibraryScreen.swift` | 存檔格子 UI + 空狀態 |
| 改 | `Sources/Museum/MuseumModels.swift` | `MuseumAnswers` 加 `: Codable` |
| 改 | `Sources/Museum/MuseumGalleryView.swift` | `MuseumGenerator` 加 `waitUntilReady()` |
| 改 | `Sources/App/AppState.swift` | `loadSavedVisit(_:)`、`saveCurrentVisit()`(進場即存 shell + 延遲 `fillImages`) |
| 改 | `Sources/Oops/OopsFlow.swift` | `OopsScreen.library` case、screenView 分支、`Visit Old World` 改導向 |
| 改 | `Sources/Oops/OopsWorldScreens.swift` | `runGeneration()` 進世界後呼叫 `saveCurrentVisit()` |
| 改 | `VisitingArtisan.xcodeproj/project.pbxproj` | 把 2 個新檔加入 app target(注意 UUID 不可重用 —— grep 既有再選) |

不裝任何套件、不需要 database。

---

## Edge cases / 注意事項

- **副作用(已確認可接受)**:空狀態移除「Visit Old World → 範例假世界」入口,但 Dev Menu → BA396(`Sources/DevMenu/DevMenuView.swift:200`)仍用 sample beats 進同一展廳 → 測試路徑不斷。
- **標題 fallback**:`museumAnswers.role` 空字串時 → 用 `story.persona`,再空 → 「Untitled visit」。
- **使用者太快離開**:進場就已存 shell → 卡片一定在;6 張沒生成完就退出 → 縮圖暫時是 `building.columns` 佔位 icon,圖在 `.ready` 後補上(若中途又重生成,同一輪保護會跳過補圖)。
- **去重**:`VisitLibrary.add` 以 `id`(UUID,每次生成新的)去重;同一次生成只會寫一筆。
- **縮圖選取**:elixir = `story.nodes.last { $0.tone == "warm" }` ?? `nodes.last`;對應的原圖縮成 512px。
- **pbxproj**:加檔時 grep 既有 UUID 區段,勿沿用看似空的序號(`...01XX` 空間非依序可用)。
- **worktree 陰影**:Xcode build 的是 main checkout 不是 worktree;驗證時注意實際 build 的是哪份。

---

## Verification(端到端驗證)

1. **單元測試**(新增,沿用 `Tests/` 的 Swift Testing + `StubURLProtocol` 範式):
   - `VisitLibrary` round-trip:`add` → `load` 回得到同一筆;`remove` 後清單為空且資料夾被刪。
   - `VisitRecord` Codable round-trip(含 `MuseumStory` / `MuseumAnswers`)。
   - 縮圖選取:給定 6 nodes(末張 warm)→ 選到 elixir。
2. **模擬器手動**(Vision Pro simulator):
   - 跑生成 → 一進 BA396 即已存卡 → 回 Home →「Visit Old World」**立刻看到卡**(縮圖可能先佔位)→ 等 ~90s 重開 library → elixir 縮圖出現。
   - 點卡 → 重進世界,6 面牆是磁碟讀回的圖、解說牌/語音正常、**無** Developing 遮罩、**無**新的 AI 請求(可看 log 確認沒打 image API)。
   - 殺 App 重開 →「Visit Old World」存檔仍在(持久化生效)。
   - 空狀態:全新安裝 →「Visit Old World」顯示空狀態提示。
3. **指令**:`xcodebuild -scheme VisitingArtisan -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build test`(實際 scheme/destination 以 repo 既有 scheme 為準)。

---

## 實作順序

1. 開分支 `feat/visit-history-library`(跨多檔的 feat,依 git 規則)。
2. `MuseumAnswers: Codable` + `MuseumGenerator.waitUntilReady()`(最小、無行為改變)。
3. `VisitRecord.swift`(模型 + `VisitLibrary`)+ 單元測試。
4. `AppState`:`loadSavedVisit` / `saveCurrentVisit`(進場即存 shell + 延遲 `fillImages`)。
5. `runGeneration()` 接上存檔 hook。
6. `OopsLibraryScreen` + `OopsScreen.library` + `Visit Old World` 改導向。
7. pbxproj 加檔 → build → 模擬器手動驗證 → 跑測試。

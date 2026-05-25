# Visiting Artisan — Xcode 專案建立步驟

> 為什麼要你手動建：Xcode 的 `.xcodeproj` 是機器生成的二進位設定檔，手寫容易壞。
> 正確做法：你在 Xcode 用精靈建好空專案，再把我寫好的 Swift 檔加進去。

---

## Step 1 — 建立 Multiplatform 專案

1. 開 Xcode → **File → New → Project**
2. 最上面選 **Multiplatform** 分頁 → 選 **App** → Next
3. 填：
   - **Product Name**: `VisitingArtisan`
   - **Organization Identifier**: `com.tommy`（隨意，反向網域格式）
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage / Testing**: 都不用勾
4. **儲存位置選：** `~/Desktop/Apple_Foundation/Vision Pro/`
   → 會建出 `Vision Pro/VisitingArtisan/VisitingArtisan.xcodeproj`

---

## Step 2 — 設定 Supported Destinations

1. 左側點專案藍色圖示 → 選 **VisitingArtisan** target
2. **General → Supported Destinations**
3. 確保有：**iPhone、iPad、Apple Vision**
   - 沒有 Apple Vision 就按 **＋** 加 **Apple Vision**（要選**原生 visionOS**，不是 "Designed for iPad"）
   - Mac 可以移除（按 −）

---

## Step 3 — 加入 Swift 原始碼

1. 我把所有 `.swift` 檔放在 `~/Desktop/Apple_Foundation/Vision Pro/Sources/`
2. 在 Xcode 左側對著 `VisitingArtisan` 群組按右鍵 → **Add Files to "VisitingArtisan"…**
3. 選 `Sources/` 裡的**所有 .swift 檔**
4. ⚠️ 重要：
   - **Copy items if needed** 打勾
   - **Add to targets: VisitingArtisan** 打勾
5. Xcode 預設產的 `ContentView.swift` 和 `VisitingArtisanApp.swift`：
   - 用我提供的 `VisitingArtisanApp.swift` **取代**預設那支（內容貼過去）
   - 預設的 `ContentView.swift` 可以**刪掉**（我們用 `RootView`）

---

## Step 4 — 加入佔位 360° 圖（v1）

1. 打開 `Assets.xcassets`
2. 把預先生成的 360° 圖拖進去，命名要對應 `WorldCatalog.swift` 裡的 `imageName`：
   - `world_calm_communal`
   - `world_open_nature`
   - `world_quiet_solitary`
   （先放 3 張，之後再加。圖怎麼生 → 見 `WORLDS.md`）
3. 還沒有圖也沒關係：app 會顯示一個 fallback 純色背景，flow 一樣能跑。

---

## Step 5 — 跑起來

| 想跑哪個 | 怎麼做 |
|---|---|
| **iPad**（驗證 quiz + 360° 環視） | 上方 scheme 選 iPad 模擬器 → ⌘R |
| **visionOS**（真沉浸 ImmersiveSpace） | scheme 選 **Apple Vision Pro** 模擬器 → ⌘R |
| **Vision Pro 實機** | 接上裝置 → 選你的 Vision Pro → ⌘R（需登入 Apple ID 簽署） |

---

## 遇到 compile error 怎麼辦

直接把錯誤訊息貼給我，我們一起修。第一次跨平台 + RealityKit 難免有小毛病，這很正常。

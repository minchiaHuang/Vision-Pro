# v1 — 生成 3 張預先準備的 360° 世界圖

> v1 不接 API，用手動生好的 360° 圖打包進 app。
> 關鍵：圖必須是 **equirectangular（等距長方）格式，長寬比 2:1**，才能正確貼在球體上。

---

## 要生成的 3 張（對應 WorldCatalog.swift）

| Assets 圖名 | 世界 | Quiz 觸發（cultural + physical） |
|---|---|---|
| `world_calm_communal` | 溫暖共處空間（不空、有連結感） | communal / home |
| `world_open_nature` | 開闊自然（山、海、留白） | nature / explore / active |
| `world_quiet_solitary` | 安靜獨處空間（留白、靜） | still / rest |

---

## 方法 A — Skybox AI（推薦，免費 tier，原生 equirectangular）

1. 開 https://skybox.blockadelabs.com/
2. 註冊免費帳號
3. 每張用對應 prompt 生成：

**world_calm_communal**
```
A warm communal indoor space, soft golden light, wooden textures,
a sense of gathering and belonging, cozy but not crowded, equirectangular 360 panorama
```

**world_open_nature**
```
An open natural landscape, distant mountains, soft sky, room to breathe,
calm and expansive, gentle daylight, equirectangular 360 panorama
```

**world_quiet_solitary**
```
A quiet solitary space, still water, soft diffused light, minimal and calm,
nothing to prove, peaceful emptiness, equirectangular 360 panorama
```

4. 下載每張（Skybox 輸出本來就是 2:1 equirectangular）→ 重新命名成上表的圖名

---

## 方法 B — 其他工具（備案）

| 工具 | 備註 |
|---|---|
| https://www.blockadelabs.com（同上） | 最直接，原生 360° |
| Midjourney `--ar 2:1` + 加 "equirectangular 360 panorama" | 比例對，但接縫可能不完美 |
| Poly / 既有 HDRI 素材庫 | 真實 360°，但非個人化 |

⚠️ 一般 Midjourney/DALL-E 直出的圖**不是真 equirectangular**，貼到球體上接縫和極點會變形。優先用 Skybox AI。

---

## 放進 Xcode

1. 開 `Assets.xcassets`
2. 把 3 張圖拖進去
3. 圖名必須**完全等於**：`world_calm_communal`、`world_open_nature`、`world_quiet_solitary`
4. ⌘R 跑起來測試

---

## 還沒生圖也能跑

`Immersive360View` / `ImmersiveWorldView` 找不到圖時會 fallback 成深灰球體，
所以你可以**先跑通整個 flow**（splash → quiz → loading → 世界環視），再補圖。

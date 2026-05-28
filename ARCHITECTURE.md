# Architecture — Visiting Artisan

> Last aligned to code state: `dab3c9d` (feat/v2-foundation, 2026-05-28)

System architecture & data flow as it actually is in the repo today. For product
reasoning see [PRD.md](PRD.md); for "what state is each pipeline in" see
[ROADMAP.md](ROADMAP.md).

---

## 1. High level

A single Xcode target whose `SUPPORTED_PLATFORMS` covers iOS, iPadOS, and visionOS.
Shared SwiftUI source under `Sources/` is used by every platform; only the
display layer of the World screen differs.

```
┌─ Shared core (pure Swift + SwiftUI, no platform deps) ──────┐
│  Models · QuizData · WorldCatalog · AppState · PromptBuilder │
└──────────────────────────────────────────────────────────────┘
                    │ World display splits per platform / pipeline
                    │
   3DoF skybox (primary)
   ├─ iOS/iPadOS  →  Immersive360View   (drag/gyro on inward sphere)
   └─ visionOS    →  ImmersiveWorldView (sphere inside ImmersiveSpace)

   6DoF USDZ spike (experimental)
   ├─ iOS/iPadOS  →  Scene3DView        (PerspectiveCamera + drag)
   └─ visionOS    →  (Day 2 of spike, sibling ImmersiveSpace pending)

   WorldLabs API spike (experimental, inert without key)
   └─ All platforms →  WorldLabsTestView (sheet from Splash)
```

**Why one target, multiple platforms:** quiz UI + state machine + world catalog
are 100% shared; only "how the world is rendered" diverges by platform and by
pipeline. The whole flow can be validated on iPad before any Vision Pro hardware
is available.

---

## 2. Three pipelines, side by side

The repo currently carries three world-rendering pipelines. They are **siblings,
not replacements** — adding the next one does not delete the previous one.

### 2.1 3DoF equirectangular skybox (primary, working)

The original v1 architecture. Still the main demo path.

| File | Role |
|---|---|
| [`Immersive360View.swift`](Sources/Immersive360View.swift) | iOS RealityView with an inward-facing sphere, drag + gyro to rotate |
| [`ImmersiveWorldView.swift`](Sources/ImmersiveWorldView.swift) | visionOS sphere inside an `ImmersiveSpace(id: "world")` |
| [`MotionManager.swift`](Sources/MotionManager.swift) | CoreMotion → quaternion for iPad landscape gyro |

How it renders, on both platforms:

1. `MeshResource.generateSphere(radius: 1000)`.
2. Flip normals inward (`scale.x = -1`) so the texture renders on the **inside**.
3. Apply the equirectangular (2:1) panorama as an `UnlitMaterial` texture from
   `Assets.xcassets/world_*.imageset`.
4. Put the camera at the sphere center (or let the user's head be the camera
   on Vision Pro) — looking out = surrounded by the world.

If the asset is missing, the material falls back to a gray tint so the flow
still runs.

### 2.2 6DoF USDZ walkable spike (in progress)

Day 1 of a 3-day spike. The goal is to evaluate whether walkable USDZ worlds can
replace or supplement the skybox, without committing to a full pivot. See
[ROADMAP.md](ROADMAP.md) for decision gates.

| File | Role |
|---|---|
| [`Scene3DView.swift`](Sources/Scene3DView.swift) | iOS `RealityView` + `PerspectiveCamera` at 1.7 m eye height; drag to look around. Joystick walking is Day 2. |
| [`SceneLoader.swift`](Sources/SceneLoader.swift) | `loadScene(for world: World) async -> Entity`; loads USDZ via `Entity(named:)` or returns a gray placeholder cube |
| [`Sources/Resources/Scenes/`](Sources/Resources/Scenes/) | `world_warm_communal.usdz`, `world_open_nature.usdz` (CC-licensed Sketchfab assets) |
| [`WorldView.swift`](Sources/WorldView.swift) (`iOSWorldView`) | Adds **"View in 6DoF (spike)"** secondary button + `.fullScreenCover` |

Sibling pattern: the spike uses its own view (`Scene3DView`) reached through a
separate button. The existing 3DoF buttons and flow are untouched, so the entire
spike can be deleted by removing one button and four files without affecting
the main path.

The visionOS sibling — `ImmersiveScene3DView` + a sibling `ImmersiveSpace(id: "world_3d")`
— is planned for Day 2 of the spike.

### 2.3 WorldLabs API spike (inert without key)

A pre-existing feasibility experiment for World Labs' Marble panorama API.
**Not integrated into the main quiz flow.** Reached only by the secondary
"Experimental: World Labs" button on the Splash screen.

| File | Role |
|---|---|
| [`WorldLabsService.swift`](Sources/WorldLabsService.swift) | API client (generate → poll → download) |
| [`WorldLabsTestView.swift`](Sources/WorldLabsTestView.swift) | Standalone UI sheet for prompt → panorama |
| [`Secrets.swift`](Sources/Secrets.swift) | API key holder (empty stub committed) |

The empty key means `WorldLabsService` reports "Missing World Labs API key"
and the spike stays inert on a fresh clone. To actually exercise it, see
[SETUP.md](SETUP.md) §Secrets.

This pipeline is **kept in the build target on purpose** — the team wants the
spike visible while figuring out whether to integrate it later. Its long-term
disposition is tracked in [ROADMAP.md](ROADMAP.md).

---

## 3. Layers (shared core)

| Layer | Files | Responsibility |
|---|---|---|
| **Model** | [`Models.swift`](Sources/Models.swift) | `QuizAnswers`, `ChoiceOption`, `World` (with `imageName`, `sceneName?`, `narrationText`) |
| **Data** | [`QuizData.swift`](Sources/QuizData.swift), [`WorldCatalog.swift`](Sources/WorldCatalog.swift) | Five-question quiz; four pre-baked worlds + `resolve(from:)` |
| **Logic** | [`PromptBuilder.swift`](Sources/PromptBuilder.swift) | `QuizAnswers → text prompt` (dormant; reserved for v2) |
| **State** | [`AppState.swift`](Sources/AppState.swift) | `@Observable` state machine (`phase`, `answers`, `world`) |
| **Entry / Nav** | [`VisitingArtisanApp.swift`](Sources/VisitingArtisanApp.swift), [`RootView.swift`](Sources/RootView.swift) | App entry, scenes, phase routing |
| **Quiz / World UI** | [`QuizView.swift`](Sources/QuizView.swift), [`WorldView.swift`](Sources/WorldView.swift) | Per-phase screens |
| **Design system** | [`DesignSystem.swift`](Sources/DesignSystem.swift) | Theme, button styles, type, orb, gradient background |

Core logic has zero UIKit / RealityKit dependency — it builds on every platform
and is independently testable.

---

## 4. State machine

`AppState.phase` drives `RootView`:

```
.splash ──Begin──▶ .quiz ──(answer Q5)──▶ .loading ──(~2 s)──▶ .world
                                                                  │
                                                          "Start over"
                                                                  ▼
                                                              .splash
```

`AppState` holds:

- `answers: QuizAnswers` — `energy`, `need`, `help`, `week`, `minutes`
- `world: World?` — resolved after the loading delay
- `finishQuiz()` — runs the loading delay, then calls `WorldCatalog.resolve(from:)`

The 6DoF spike entry sits **inside** `.world` — it pushes `Scene3DView` over the
existing `Immersive360View` via `fullScreenCover`, so the state machine itself
does not change.

---

## 5. Data flow (end-to-end)

```
User answers 5 questions
   │  AppState.answers (energy, need, help, week, minutes)
   ▼
WorldCatalog.resolve(from:) ─▶ World { imageName, sceneName?, narrationText }
   │
   ├──── 3DoF path (default) ────▶ Immersive360View / ImmersiveWorldView
   │                                  (equirectangular sphere)
   │
   └──── 6DoF path (user taps "View in 6DoF (spike)") ────▶ Scene3DView
                                      (SceneLoader → USDZ Entity, or placeholder)
```

`PromptBuilder` exists but is currently dormant — it's wired in to become the
prompt source if/when a generative pipeline (Skybox AI or Marble) is adopted.

---

## 6. Catalog mapping

`WorldCatalog.resolve()` maps `QuizAnswers` to one of four worlds. Priority:

1. `week == "sleep" && (need == "quiet" || help == "alone")` → `starry_night`
2. `week == "home" || need == "connection" || help == "talk"` → `warm_communal`
3. `need == "movement" || "creativity" || help == "move" / "make" || energy > 0.65` → `open_nature`
4. `need == "quiet" || help == "alone" || energy < 0.35 || week == "exam" / "focus" / "sleep"` → `quiet_solitary`
5. Default → fallback (warm room)

> The dimensions the quiz currently captures (`energy / need / help / week / minutes`)
> don't fully cover the original PRD's three-dimension framing (Emotional / Cultural /
> Physical). That's a known **research gap** — see [PRD.md](PRD.md) §9.

---

## 7. Conventions

- Platform-specific files are guarded with `#if os(visionOS)` / `#if !os(visionOS)`.
- Core logic has zero UIKit / RealityKit dependency → testable and shared.
- `Sources/Secrets.swift` is **committed** as an empty stub so clean clones build.
  Real keys are overridden locally and never committed. See [SETUP.md](SETUP.md) §Secrets.
- 6DoF assets are committed under `Sources/Resources/Scenes/` and registered as
  `Resources` build phase entries in `project.pbxproj`.
- AppIcon: solid layered visionOS icon (`AppIcon.solidimagestack/`) + classic
  `AppIcon.appiconset/` for iOS, wired via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
  in target Debug + Release configs.

---

## 8. Extension points

| Future work | Where it plugs in | Notes |
|---|---|---|
| **Voice-over narration** | New `Narrator.swift` (AVSpeechSynthesizer) + `NarrationOverlay.swift`, triggered in `WorldView.onAppear` | `World.narrationText` field already exists |
| **6DoF visionOS sibling** | New `ImmersiveScene3DView.swift` + sibling `ImmersiveSpace(id: "world_3d")` in `VisitingArtisanApp.swift` | Day 2 of the 6DoF spike |
| **Virtual joystick** | New `VirtualJoystick.swift` SwiftUI overlay, `Binding<SIMD2<Float>>` → camera translate in `Scene3DView` | Day 2 of the 6DoF spike |
| **Live AI generation (Skybox / Marble)** | New service replacing `WorldCatalog.resolve` in `AppState.finishQuiz()` | `World.imageURL` already exists for remote loading; not on the 3-week roadmap |
| **More quiz questions** | Append to `QuizData.questions` | UI auto-adapts (progress dots, one-per-screen) |
| **New worlds** | Add to `WorldCatalog.all` + drop assets into `Assets.xcassets/` and/or `Sources/Resources/Scenes/` | Update `resolve()` priority |

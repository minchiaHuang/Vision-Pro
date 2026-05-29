# Architecture — Visiting Artisan

> System architecture & data flow. For product reasoning see [PRD.md](PRD.md).

---

## 1. High-level

A single Xcode project with two targets (iOS/iPadOS + visionOS) sharing one core logic layer.
Only the **display layer** differs per platform.

```
┌─ Shared core (pure Swift + SwiftUI, no platform deps) ──────┐
│  Models · QuizData · PromptBuilder · WorldCatalog · AppState │
└──────────────────────────────────────────────────────────────┘
                    │ display layer splits per platform
   iOS/iPadOS  →  Immersive360View   (drag/gyro to look around a sphere)
   visionOS    →  ImmersiveWorldView (true immersive ImmersiveSpace)
```

**Why this split:** quiz UI + logic are 100% shared; only *how the world is shown* is
platform-specific. So the entire flow can be validated on iPad before any Vision Pro hardware.

---

## 2. Layers

| Layer | Files | Responsibility |
|---|---|---|
| **Model** | `Models.swift` | `Dimension`, `QuizQuestion`, `QuizOption`, `QuizResult`, `World` |
| **Data** | `QuizData.swift`, `WorldCatalog.swift` | Quiz questions; pre-baked worlds + lookup |
| **Logic** | `PromptBuilder.swift` | `QuizResult` → text prompt (display now, Skybox API later) |
| **State** | `AppState.swift` | `@Observable` flow state machine (phase, result, world) |
| **Entry/Nav** | `VisitingArtisanApp.swift`, `RootView.swift` | App entry, phase-based view switching |
| **Views** | `QuizView.swift`, `WorldView.swift`, `RootView.swift` | Splash, quiz, loading, world |
| **Display** | `Immersive360View.swift` (iOS), `ImmersiveWorldView.swift` (visionOS) | 360° sphere rendering |
| **Voice (v4 · 6a)** | `NarrationService.swift`, `NarrationComposer.swift` | On-device TTS entry narration: composes a welcome from `AxisScores` and speaks it via `AVSpeechSynthesizer` when `.world` appears. No mic, no network, no permissions |
| **Voice (v4 · 6b)** | `ConversationService.swift` (planned) | Mic → STT → cloud LLM → TTS conversation loop; runs during `.world` phase. Reuses `NarrationService` as its TTS stage |

---

## 3. State machine

`AppState.phase` drives `RootView`:

```
.splash ──Begin──▶ .quiz ──(answer last Q)──▶ .loading ──(~2s)──▶ .world
                                                                     │
                                                            "Start over"
                                                                     ▼
                                                                 .splash
```

`AppState` (in `AppState.swift`) holds:
- `result: QuizResult` — accumulates one tag per dimension
- `world: World?` — resolved after quiz
- `finishQuiz()` — runs the loading delay, then `WorldCatalog.resolve(from:)`

---

## 4. Data flow (end-to-end)

```
User taps options
   │  AppState.answer(dimension, tag)
   ▼
QuizResult { emotional, cultural, physical }
   │
   ├─▶ PromptBuilder.prompt(from:)  → text prompt
   │        e.g. "An immersive 360 environment that feels calm and serene,
   │              warm communal space..., still water..."
   │        (v1: display only; v2: sent to Skybox AI API)
   │
   └─▶ WorldCatalog.resolve(from:) → World   ← v1 lookup table
                                              ← v2 replaced by SkyboxService (live gen)
   ▼
World { imageName / imageURL }
   │  display layer
   ├─ iOS:     Immersive360View    — equirectangular texture on inward sphere, camera at center
   └─ visionOS: ImmersiveWorldView — same sphere inside ImmersiveSpace, head = camera
```

---

## 5. 360° rendering (both platforms)

The same idea on iOS and visionOS:

1. Generate a large sphere mesh (radius 1000).
2. Flip normals inward (`scale.x = -1`) so the texture shows on the **inside**.
3. Apply the equirectangular (2:1) 360° image as an `UnlitMaterial` texture.
4. Put the camera at the sphere center → looking out = surrounded by the environment.

- **iOS/iPadOS:** `RealityView` + `DragGesture` rotates the sphere (look around).
- **visionOS:** `ImmersiveSpace` + `RealityView`; the user's head is the camera (6DOF look, no walking in v1).

If the image asset is missing, both fall back to a grey sphere — so the flow always runs.

---

## 6. Extension points

| Future | Where it plugs in | Note |
|---|---|---|
| **v2 live generation** | new `SkyboxService`, replaces `WorldCatalog.resolve` in `AppState.finishQuiz()` | `World.imageURL` already exists for remote images |
| **v4 · 6a entry narration** | `NarrationService` (TTS) + `NarrationComposer` (text), triggered in `iOSWorldView.task` | done — on-device `AVSpeechSynthesizer`, no deps/keys/permissions; mascot = reused `OrbView` |
| **v4 · 6b AI voice companion** | new `ConversationService`, activated in `.world` phase; reuses `NarrationService` as its TTS stage | spike first (speech-to-chat, cloud LLM — needs key/package approval); deepen into a reflection mentor later |
| **v5 AI-generated walkable worlds** | new display pipeline (splat/mesh) replacing the sphere | World Labs Marble; significant display-layer change |
| **More quiz questions** | append to `QuizData.questions` | UI auto-adapts (progress dots, one-per-screen) |
| **New worlds** | add to `WorldCatalog.all` + Assets | update `resolve()` mapping |

---

## 7. Conventions

- Platform-specific files are guarded with `#if os(visionOS)` / `#if !os(visionOS)`.
- Core logic has zero UIKit/RealityKit dependency → testable & shared.
- API keys never committed (see `.gitignore`); v2 keys go in an untracked `Secrets.swift`.

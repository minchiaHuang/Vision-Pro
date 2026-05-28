# Visiting Artisan

> Last aligned to code state: `dab3c9d` (feat/v2-foundation, 2026-05-28)

> An Apple Vision Pro + iPad SwiftUI prototype: answer five soft questions and
> step into a personalised immersive world that reflects who you are right now.

**Status:** 🛠️ Working prototype · Apple Foundation Program project + personal portfolio · 6DoF spike in progress

---

## What it is

Most balance / wellness apps ask *"how do you feel today?"* — Visiting Artisan asks **"who are you right now?"**

You answer a short, five-question quiz (energy slider · what you need · what helps · this week's shape · how much time you have), and the app drops you into one of four immersive worlds that matches your current state.

**Core thesis:** Self-alignment = Balance. You can't align with a self you don't know.

> ℹ️ The quiz currently has **five soft questions** rather than the original three-dimension (Emotional / Cultural / Physical) framing. That dimensional design is a **research gap** the group hasn't re-converged on yet — see [PRD.md](PRD.md) §9.

---

## Demo flow

```
Splash  →  five-question quiz  →  "Weaving..." transition  →  immersive world
```

- **iPad / iPhone:** drag (or use the gyroscope) to look around a 360° panorama
- **Apple Vision Pro:** real immersion — your head is the camera, you stand inside the world
- **6DoF spike (experimental):** in the World view, tap **"View in 6DoF (spike)"** to load a walkable USDZ scene instead of the 360° skybox (iOS only for now)

---

## The four worlds

| World ID | Title | Skybox asset | Walkable USDZ |
|---|---|---|---|
| `starry_night` | Under a Sky Made of Quiet | ❌ (gray fallback) | ❌ (placeholder cube) |
| `open_nature` | A Horizon With Room to Move | ✅ `world_open_nature` | ✅ `world_open_nature.usdz` |
| `warm_communal` | A Room That Lets You Exhale | ❌ (gray fallback) | ✅ `world_warm_communal.usdz` |
| `quiet_solitary` | A Quiet Worth Returning To | ✅ `world_quiet_solitary` | ❌ (placeholder cube) |

Both rendering paths fall back gracefully when an asset is missing — the app never crashes, you just see a gray sphere or a labelled placeholder cube. See [WORLDS.md](WORLDS.md) for sources and what still needs sourcing.

---

## Project layout

```
Vision-Pro/
├── README.md              ← you are here
├── PRD.md                 ← product thesis + research gaps
├── ARCHITECTURE.md        ← code architecture (3 pipelines, sibling pattern)
├── ROADMAP.md             ← pipeline status + decision gates
├── SETUP.md               ← build & run, verify.sh
├── WORLDS.md              ← world asset manual (skybox + USDZ)
├── VisitingArtisan.xcodeproj   ← single target, multi-platform (iOS + visionOS)
├── Assets.xcassets        ← AppIcon (lantern), AccentColor, scene illustrations, world skyboxes
├── Sources/               ← shared Swift source
│   └── Resources/Scenes/  ← USDZ assets for the 6DoF spike
└── bin/
    └── verify.sh          ← clean-build smoke test (iPad + Vision Pro sims)
```

---

## Getting started

1. Open `VisitingArtisan.xcodeproj` in Xcode 26.5 or newer.
2. Pick the `iPad Pro 13-inch (M5)` simulator (or the `Apple Vision Pro` simulator).
3. ⌘R.

No API keys are required for the main flow. The "Experimental: World Labs" button on the splash screen is a spike entry point and will report "Missing API key" with the empty stub in `Sources/Secrets.swift` — that is the expected behavior on a fresh clone.

For details, see [SETUP.md](SETUP.md). For everything that exists in the repo and why, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Tech stack

Swift · SwiftUI · RealityKit · `ImmersiveSpace` (visionOS) · CoreMotion (iPad gyro) · AVFoundation (planned for narration)

**Platforms:** one Xcode target, multi-platform (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator xros xrsimulator`). iOS 26 / visionOS 26 deployment targets.

---

## Pipelines (snapshot)

Three world-rendering pipelines coexist in the repo right now:

| Pipeline | Status | Where |
|---|---|---|
| **3DoF skybox** (primary) | ✅ Working | `Immersive360View` (iOS), `ImmersiveWorldView` (visionOS) |
| **WorldLabs API spike** | 🧪 Inert without key | `WorldLabsService` + `WorldLabsTestView`, reached from Splash |
| **6DoF USDZ spike** | 🧪 In progress (Day 1 of 3) | `Scene3DView` (iOS), `SceneLoader`; visionOS sibling pending |

The 6DoF spike has not yet been chosen as the product direction — Day 3 review will decide PROCEED / RETREAT / DETOUR. See [ROADMAP.md](ROADMAP.md).

---

## Documentation

- [PRD.md](PRD.md) — product thesis, persona, research gaps
- [ARCHITECTURE.md](ARCHITECTURE.md) — code structure, three pipelines, sibling pattern
- [ROADMAP.md](ROADMAP.md) — pipeline status, decision gates, spike outcome triggers
- [SETUP.md](SETUP.md) — build & run, `bin/verify.sh`, simulator names, known caveats
- [WORLDS.md](WORLDS.md) — world catalogue, asset sources (Poly Haven CC0, ESO CC BY, Sketchfab), naming

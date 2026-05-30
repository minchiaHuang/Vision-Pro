# Visiting Artisan — PRD & Technical Architecture

> Apple Vision Pro app　|　AFP project + personal portfolio
> Document version: v0.1 (2026-05-25)

---

## 1. Product Overview

**In one line:** an app that generates your own immersive world from a "Who are you?" quiz,
letting university students *feel* — not just understand — what their balance looks like.

| | |
|---|---|
| **App name** | Visiting Artisan |
| **Platform** | Apple Vision Pro (primary) + iPad/iPhone (validation + daily entry point) |
| **Challenge Statement** | Helping individuals achieve balance through authentic self-alignment |
| **App Statement** | An app that helps university students understand who they are, by guiding them through a personalised quiz and immersing themselves in a world that they describe, letting them feel what their authentic self feels like. |
| **Core belief** | Self-alignment = Balance. You can't align with a self you don't know, so "understanding who you are" is a necessary precondition for "achieving balance". |

**Scope (stated honestly):** this product is about "**discovery + experience**" — the first
mirror, turning abstract balance into something you can step into and feel. **Daily
maintenance** is a later direction and is out of scope for v1–v3.

---

## 2. Target User

**Primary persona: Aisha Mensah — "I Am What I Produce"** (achievement-driven; see the
AFP day-05 notes)

- 22 years old, second-year IT student, UTS
- Equates productivity/achievement with overall wellbeing; doesn't know who she is beyond
  being a "high-achieving student"
- Skips anything that looks like a "self-reflection" tool
- **Hook (entry point):** not wellness, but tech novelty — "a 2-minute quiz generates your
  own Vision Pro world" is fun, low-commitment, and shareable to her. The wellness gap only
  surfaces passively after she's in.

---

## 3. Core User Flow

```
Splash (app name)
    ↓
"Who are you?" Quiz (3 dimensions, 1–2 questions each)
    ↓
"Building your world…" (transition / loading)
    ↓
Your immersive world (walkable 3D)
    ↓
Talk with an AI voice companion (v4: speech-to-chat first, later deepened into a
"guided reflection" mentor)
    ↓
(later) daily entry point: return to your space
```

Corresponding user stories:
1. As a user, I want to answer a "Who are you?" quiz so that I can get my own personalised immersive world.
2. As a user, I want to step into my generated world so that I can *feel* — not just understand — what my balance looks like.
3. As a user, I want to return to my space so that I can rebalance in daily life.

---

## 4. Quiz Design

> ⚠️ **This section needs more research** (see §9). The following is a working draft, not final.

3 dimensions; the answer for each dimension maps to a visual parameter of the generated world:

| Dimension | Question (draft) | Options | What it affects in the world |
|---|---|---|---|
| **Emotional** | When you feel off-balance, what do you need most? | Quiet alone / Talk to someone / Move your body / Create something | Mood, lighting, colour temperature |
| **Cultural** | Where do you feel most like yourself? | In nature / Around people / At home / Somewhere new | Scene elements: communal vs solitary space, cultural symbols |
| **Physical** | How does your body recharge? | Stillness / Movement / Sensory calm / Rest | Landscape type: open and dynamic vs quiet and spare |

**The Cultural dimension's mechanism (the key differentiator):**
- Collective/family-oriented → warm communal space, gathering scenes, familiar cultural
  symbols (not deserted)
- Individual/independent-oriented → open solitary space, quiet, negative space
- vs Western-centric competitors (TRIPP, etc.): their default "balance" is an ethereal
  beach; for people from collective cultural backgrounds, balance might be a lively family
  kitchen.

---

## 5. Technical Architecture

**Strategy: one Xcode project, two targets, sharing the core logic.**

```
┌─ Shared (used by iPad + visionOS, pure Swift, no UI dependency) ──┐
│  Models/                                               │
│    QuizQuestion, QuizAnswer, QuizResult                │
│    World (id, title, imageName/imageURL, description)  │
│  Logic/                                                │
│    PromptBuilder   : QuizResult → text prompt          │
│    WorldResolver   : QuizResult → World (v1 lookup)    │
│    SkyboxService   : prompt → 360° image (API in v2)   │
└─────────────────────────────────────────────────────────┘
            ↓ display layer splits by platform
  iOS/iPadOS target:
    QuizView (SwiftUI) → WorldView
    360 viewer: RealityKit sphere mesh, equirectangular image on the inner wall
    touch drag / CoreMotion gyroscope to look around
  visionOS target:
    QuizView (SwiftUI, windowed)
    ImmersiveSpace: sphere skybox, true immersion
```

**Why split it this way:**
- Quiz UI and logic are 100% shared across both platforms (SwiftUI + pure Swift models)
- Only "how the world is displayed" splits by platform: iPad is a look-around 360° (for
  validation), visionOS is true immersion
- Without a Vision Pro on hand, the iPad/simulator can still run the full flow

**360° display principle (common to both platforms):**
- Build a large sphere mesh with normals flipped inward
- Apply the equirectangular (2:1) 360° image as the material on the sphere's inner wall
- Place the camera at the sphere's centre → looking outward gives a surrounding environment
- visionOS uses `ImmersiveSpace` + RealityKit; iPad uses `RealityView` or SceneKit, with the
  camera rotating by gesture/gyroscope

---

## 6. End-to-End Pipeline ("can the whole thing run")

```
Quiz answers (QuizResult)
    ↓ PromptBuilder
text prompt
  e.g. "calm, warm communal interior, soft light, gathering space"
    ↓
  v1: WorldResolver lookup → a matching pre-generated bundled image   ← no network/API
  v2: SkyboxService → Skybox AI REST API → live 360° image            ← needs API key
    ↓
World(image)
    ↓ display layer
  iPad: sphere 360° look-around
  visionOS: ImmersiveSpace true immersion
```

**v1 runs the full flow entirely locally with zero external dependencies** — that is the
answer to "let's first see whether the whole thing runs end to end": yes.

> **Display-layer note:** the `SkyboxService` of v1/v2 maps to the **Skybox AI API** (360°
> equirectangular → sphere texture); the existing `Immersive360View` / `ImmersiveWorldView`
> consume that kind of image directly.
> When v5 switches to Marble, the display layer must change from "sphere texture" to
> "splat / mesh scene" — that is **a separate display pipeline** (see the §6.5 decision).

---

## 6.5 World Generation Backend — Decision

> World generation relies on an external product. The market splits into two categories, and
> the difference drives the whole display pipeline and engineering effort. Verified against
> the latest 2026 status.

| Category | Representative | Experience | Into Vision Pro |
|---|---|---|---|
| **360° skybox** | **Skybox AI** (Blockade Labs) | Stand and look around, surrounded (can't walk) | ✅ Simple: equirectangular image on a sphere's inner wall |
| **Walkable 3D world** | **World Labs Marble** | 6DOF walk-around exploration | ⚠️ Heavy: Gaussian splat / mesh rendering |

### ✅ Decision: use Skybox AI for v1–v3; upgrade to Marble as a v4 stretch

**Why Skybox AI first:**
- Fully matches the existing architecture (sphere skybox); zero code rewrite
- Official visionOS / Vision Pro spatial support
- For the emotional goal (being surrounded by your world, feeling balance), 360°
  look-around is immersive enough
- Feasible and cheap for a student; aligns with "without AI unless needed" (v1 pre-baked images)

### Verified facts (2026)

| Product | Highlights |
|---|---|
| **Skybox AI** | equirectangular up to 8K (Business 16K); official visionOS/Vision Pro spatial support page; **API is on Business at $112/mo**; manual generation on Essential $20/mo or a free trial |
| **World Labs Marble** | text/image/video → walkable 3D world; export Gaussian splat (PLY)/mesh (GLB)/video; has a **World API**; viewable natively on Vision Pro; PLY→USDZ needs NVIDIA Omniverse NuRec |
| **Middle option** | visionOS 26 Photos has a built-in one-tap **Spatial Scene** (Apple open-source on-device Gaussian splatting, SHARP) — single image → volumetric scene; a viable lightweight exploration path |

> 💰 **Cost reminder:** Skybox's **API is only on Business at $112/mo**. So for v1/v2, lean on
> **manual generation / the Essential tier**, and only call the API when you genuinely need
> "quiz → live generation", to avoid burning budget too early.

Sources:
- [Skybox AI for Spatial Applications (Vision Pro/XR)](https://www.blockadelabs.com/industries/skybox-ai-for-spatial-applications)
- [Skybox API documentation](https://api-documentation.blockadelabs.com/api/skybox.html)
- [World Labs — Marble World Model](https://www.worldlabs.ai/blog/marble-world-model)
- [Marble Mesh Export documentation](https://docs.worldlabs.ai/marble/export/mesh)
- [MetalSplatter (open-source visionOS splat rendering)](https://github.com/scier/MetalSplatter)

---

## 7. Phasing

> **Direction change:** v1 (the whole flow runs, pre-baked 360° via lookup) is done; the
> original v2 "Skybox AI live 360° generation" is **skipped** — we jump straight onto the
> "walkable world" track. The phases below are numbered from where we are now, **v3**.

| Phase | Goal | Display | World source | External sign-up | Status |
|---|---|---|---|---|---|
| **v3** | Walkable 3D world | Vision Pro / iPad, 6DOF walk-around | Pre-made USDZ mesh scenes | ❌ None (local USDZ) | 🔵 In progress (USDZ mesh + PS5 controller spike) |
| **v4** | **AI voice conversation** (a companion/mentor inside the world) | In-world voice interaction | — | Conversation LLM (on-device or API) | 🔵 6a entry narration ✅ (built-in `AVSpeechSynthesizer` TTS, no permissions; `NarrationService` + `NarrationComposer`); 6b two-way speech-to-chat ✅ spike (`SFSpeechRecognizer` STT → Claude Messages API via URLSession, Haiku 4.5 → TTS; `ConversationService` + `SpeechRecognizer`, needs mic/speech permission + a local `anthropicAPIKey`); the "AI mentor guided reflection" persona / question design is deferred until after the §9 research |
| **v5** | Walkable **+ AI live generation** of the world | Same as above | World Labs Marble (World API → splat / mesh) | Marble API + splat/mesh rendering integration | ⬜ Not started (was v4) |
| **v6** | Deploy on Vision Pro hardware | Vision Pro device | Same as v5 | Apple Developer (free tier runs on your own device) | ⬜ Last (was v5) |

> **v4 splits in two:** first **6a entry narration** (when you enter the world, the guide
> uses your quiz scores + archetype to "introduce your world", pure built-in TTS, zero
> keys/permissions, verifiable on the iPad simulator) ✅; then **6b two-way speech-to-chat
> (microphone → STT → cloud LLM → TTS)**, kept as a spike, requiring prior approval of the
> package/keys; decide whether to invest fully only after feeling the latency on a real
> device — don't commit to finishing it before headset validation.
> v5 upgrades "pre-made walkable scenes" into "AI-generated walkable worlds" (the display
> layer keeps the splat/mesh pipeline). v6 deploys the finished product onto Vision Pro hardware.

---

## 8. Data Model (v1)

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
    let tag: String            // keyword used to build the prompt / do the lookup
}

struct QuizResult {
    var answers: [Dimension: String]   // dimension → chosen tag
}

struct World: Identifiable {
    let id: String
    let title: String          // e.g. "This is what balance feels like for you"
    let imageName: String      // v1: asset name bundled into the app
    let imageURL: URL?         // v2: returned by the API
    let blurb: String
}
```

---

## 9. Research Still Needed (gaps stated honestly)

> These are to be filled in after v1. They don't affect v1 running, but they affect the
> product's persuasiveness.

1. **Personalised question design** — the current quiz questions are a working draft. Research needed:
   - Which questions truly elicit "self-alignment / authentic self" rather than mere preference?
   - How to ask the cultural dimension without being shallow or stereotyping?
   - How many questions are enough (too few is inaccurate, too many and Aisha bails)?
2. **Answer → world mapping** — what kind of visuals actually make someone feel "aligned with
   themselves"? Needs user testing.
3. **Surfacing Aisha's gap after entry** — once she's in, how does the app passively let her
   see the gap between "the self she assumed" and "the generated world"?
4. **Extending toward "achieve"** — daily entry point, rebalance mechanism (v3+ scope).
5. **v5 Marble feasibility** — the personalisation cost/latency of quiz → Marble prompt, and
   the rendering performance of Gaussian splat on Vision Pro, both need real measurement to
   confirm whether v5 is worth doing.
6. **AI voice companion/mentor (v4)** — what should it ask to genuinely tie back to
   self-alignment (rather than small talk)? Persona and tone? How to close out a multi-turn
   conversation? How do voice latency and naturalness feel in the headset (only judgeable on
   real hardware)? Voice-data privacy, and the on-device vs cloud trade-off.

---

## 10. Tech Stack

| Item | Choice |
|---|---|
| Language | Swift |
| UI | SwiftUI |
| 3D / 360° | RealityKit (sphere skybox) |
| Immersion | visionOS `ImmersiveSpace` |
| iPad look-around | `RealityView` + CoreMotion / gestures |
| Networking (v2) | URLSession → Skybox AI REST API |
| Image generation (v2) | Skybox AI (Blockade Labs), text → 8K 360° equirectangular |
| World generation (v5) | World Labs Marble (World API) → Gaussian splat / mesh |
| Splat rendering (v5) | MetalSplatter (open source) or mesh (GLB) imported into RealityKit; or PLY→USDZ via Omniverse NuRec |
| Lightweight middle option | visionOS 26 built-in Spatial Scene (single image → volumetric scene) |
| Speech input STT (v4) | Speech framework / iOS 26 SpeechAnalyzer |
| Speech output TTS (v4) | AVSpeechSynthesizer (or a more natural third-party/cloud TTS) |
| Conversation AI (v4) | LLM — on-device Foundation Models or a cloud API |
| Spatial audio (v4, visionOS) | RealityKit spatial audio, positioning the companion's voice inside the world |
| IDE | Xcode 26.5 |

---

## 11. v1 Definition of Done

- [ ] App launches → Splash → Quiz (3 dimensions)
- [ ] Quiz done → loading transition
- [ ] Lookup by answers → display the matching pre-generated 360° world
- [ ] iPad: drag/gyroscope to look around the whole world
- [ ] visionOS simulator: immersive display via ImmersiveSpace
- [ ] At least 3 answer combinations → 3 noticeably different worlds (so personalisation is felt)

# Architecture — Visual Eyes (Future Museum)

> System architecture & data flow. For product reasoning see [PRD.md](PRD.md).
> (Supersedes the v0.1 "360° skybox" architecture.)

---

## 1. High-level

A single Xcode project sharing one core logic layer. The **generation pipeline** (answers →
story → images) is pure networking + models; only the **display layer** (how the museum is
walked) and the **voice layer** differ by platform.

```
┌─ Shared core (Swift, no platform deps) ────────────────────────────────┐
│  Museum models · CuratorService · ImageGenerationService · AppState     │
└──────────────────────────────────────────────────────────────────────────┘
                    │ display layer splits per platform
   iOS/iPadOS  →  ParametricWorldView   (first-person camera rig in the USDZ)
   visionOS    →  ImmersiveWorldView    (true immersion; head = camera + locomotion)
                    │ voice layer (both platforms)
                  ConversationService    (per-beat narration + push-to-talk Curator)
```

**Why this split:** the questions, the Curator pipeline, and the story/voice grounding are 100%
shared; only *how the museum is walked* is platform-specific. The whole flow can be validated on
iPad before any Vision Pro hardware.

---

## 2. Layers

| Layer | Files | Responsibility |
|---|---|---|
| **Museum models** | `Sources/Museum/MuseumModels.swift` | `MuseumAnswers`, `MuseumNode`, `MuseumStory`, `GeneratedNode` |
| **Stage A (Curator)** | `Sources/Museum/CuratorService.swift`, `MuseumPrompt.swift` | answers → `MuseumStory` (OpenAI Responses, `gpt-5.5`, strict `json_schema`); system prompt + dancer few-shot + schema |
| **Stage B (painter)** | `Sources/Museum/ImageGenerationService.swift` | each beat's `image_prompt` → image `Data` (OpenAI Images, `gpt-image-2`) |
| **Pipeline driver** | `Sources/Museum/MuseumGalleryView.swift` (`MuseumGenerator`) | runs Stage A then Stage B in parallel; phases `idle → writing → painting → ready` |
| **Flow** | `Sources/Museum/MuseumFlowView.swift`, `MuseumQuestionsView.swift` | questions → generating → enter museum |
| **State** | `Sources/App/AppState.swift` | `@Observable` flow state; holds `museumStory`, `museumAnswers`, `galleryImages`, `worldParams` |
| **Display** | `Sources/World/ParametricWorldBuilder.swift`, `ImmersiveWorldView.swift`, `WorldView.swift` | load the Richards Gallery USDZ, hang the images, light it, walk it |
| **Voice** | `Sources/Voice/ConversationService.swift`, `SpeechRecognizer.swift`, `NarrationService.swift`, `Azure/ElevenLabs/Speech` voices | STT → Claude → TTS; per-beat narration + push-to-talk |
| **Proximity narration** | `Sources/Museum/MuseumNarrationDirector.swift` *(phase 2)* | fires `nodes[i].narration` when the walker enters frame *i*'s radius |
| **Entry/Nav** | `Sources/App/VisitingArtisanApp.swift`, `DevMenu/DevMenuView.swift` | app entry; Dev Menu launcher (Future Museum / Oops / Voice / Splat) |

---

## 3. The two-stage pipeline

```
MuseumAnswers
   │  CuratorService.generate()              ← Stage A (blocking)
   │    POST /v1/responses · gpt-5.5 · text.format json_schema (strict)
   ▼
MuseumStory { persona, cold_style, warm_style, decision_prompt, nodes:[5] }
   │  MuseumGenerator maps each node → GeneratedNode, then:
   │  withTaskGroup { ImageGenerationService.image(forPrompt:) }   ← Stage B (parallel)
   ▼
each GeneratedNode.image = Data   (a failed beat keeps its slot, marked .failed)
```

- The strict JSON schema guarantees Stage A's `output_text` decodes straight into `MuseumStory`
  — no fragile parsing. A few-shot dancer turn teaches tone + the symbolic, text-free imagery.
- Stage B prompts are self-contained (each begins with the run's locked style string), so the
  five images stay visually consistent and there is no second LLM dependency.
- `MuseumGenerator.orderedGalleryImages()` flattens the nodes to a **fixed 5-slot, beat-ordered**
  `[UIImage]` (placeholder for any failed beat) — the invariant the display + narration rely on.

---

## 4. Display — hanging the images & walking the museum

The Richards Gallery USDZ is loaded by `ParametricWorldBuilder.build(params:galleryPhotos:)`:

1. Load the archetype USDZ (`WorldArchetype.artGallery`).
2. **Hang the photos:** `applyGalleryPhotos` finds every wall-frame mesh whose name contains
   `bake` (excluding the door and butterfly), sorts them into a stable order, and replaces each
   frame's material with an `UnlitMaterial` showing image *i*. Reusing each mesh's existing UVs
   keeps the photo correctly placed on the wall. **Beat order = frame order** (the same ordered
   list also drives proximity narration, so image-on-wall and voice-on-wall always agree).
3. Add directional lights; the gallery uses neutral params so its baked lighting reads correctly.

- **visionOS** (`ImmersiveWorldView`): the world is parented under a root the `ParametricLocomotor`
  moves each frame (player walks → world shifts opposite); head tracking adds local 6DoF.
- **iOS/iPadOS** (`ParametricWorldView`): a `PerspectiveCamera` + `WorldCameraRig` walks the same
  scene by gesture.

---

## 5. Voice — one authority, two modes

`ConversationService` owns the audio session for the whole visit so recording and playback never
clobber each other. It is configured once per visit with the Curator persona:

```
configureCurator(story:answers:)  → documentary-Curator system prompt grounded in
                                     persona + the 5 beats + fear/sacrifice/worthIt + decision_prompt
```

- **Narration (one-way):** `MuseumNarrationDirector` ticks from the locomotion update; when the
  walker first enters frame *i*'s radius it calls `convo.narrate(nodes[i].narration)`. A pure
  `frameToTrigger(playerXZ:frameXZ:fired:radius:)` makes the trigger logic unit-testable.
- **Conversation (push-to-talk):** the floating orb taps into `beginListening()` /
  `finishListeningAndReply()` → STT → Claude → TTS. Replies are 2–3 spoken sentences, grounded in
  this exhibition, handing the choice back.
- **TTS routing:** cloud voice (Azure ▸ ElevenLabs) when a key is present, else on-device
  `AVSpeechSynthesizer`. A cloud failure falls back to AVSpeech via an `onFailure` hook and trips
  a per-session circuit breaker — the guide is never silent.

Both modes go through the **same** `ConversationService` instance, so narration and conversation
share the audio session and interrupt cleanly rather than overlapping.

---

## 6. State machine & windows

`AppState` is `@Observable`. The Future Museum runs as its own coordinator (`MuseumFlowView`),
not the legacy `AppState.phase` machine:

```
.questions ──Build──▶ .generating ──(story+images ready)──▶ enterMuseum()
                                                              │ visionOS: openImmersiveSpace("world")
                                                              │           + museum-gallery-controls window
                                                              │           + museum-voice-orb window
                                                              └ iPad:    in-cover ParametricWorldView
```

visionOS uses separate `Window`s for the floating controls (locomotion + the closing decision +
Leave) and the voice orb, because a full-immersion `ImmersiveSpace` can't host SwiftUI controls
inside it. Each is a single `Window` with `restorationBehavior(.disabled)` so re-entry can't stack
stale panels.

---

## 7. Conventions

- Platform-specific files are guarded with `#if os(visionOS)` / `#if !os(visionOS)`.
- Core logic (models, pipeline, prompt builders, the proximity trigger) has zero RealityKit/UIKit
  dependency → testable & shared (Swift Testing).
- API keys never committed: `Sources/Core/Secrets.swift` ships with empty placeholders; real keys
  stay unstaged (see [SETUP.md](SETUP.md)).

---

## 8. Earlier flows kept in the repo (labelled legacy)

These are prior explorations behind their own Dev Menu entries — kept, not the current spine
(see PRD §9):

- **Oops glass flow** (`Sources/Oops/`): dark-glass visionOS prototype Opening → Home → Safety →
  Privacy → Quiz → Generating → Gallery → Reflection, with an *inspiring*-toned Hero's-Journey
  image gallery (`Sources/World/OpenAIImageService.swift`). The Museum is its *honest*-toned
  successor and reuses the same wall-hanging mechanism.
- **Splat spike** (`Sources/Spikes/`): World Labs Marble `.spz`, 6DoF walkable via
  CompositorServices / MetalSplatter — the "heavy" walkable-world path.
- **Parametric quiz/world** (`Sources/Quiz/`, `WorldMapper`): the 4+1-axis personality quiz →
  `WorldParams`; the gallery archetype reuses its builder.

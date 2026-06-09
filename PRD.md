# Visual Eyes — PRD & Technical Architecture

> Apple Vision Pro app　|　AFP project + personal portfolio
> Document version: v0.2 (2026-06-08) — **Future Museum** direction
> (supersedes v0.1's "Visiting Artisan / 360° skybox" framing)

---

## 1. Product Overview

**In one line:** ask who you want to become, then walk a five-room museum that shows that
future *honestly* — mostly its cost, not its glory — and hands the choice back to you.

| | |
|---|---|
| **App name** | Visual Eyes (Xcode project/target still named `VisitingArtisan`) |
| **Platform** | Apple Vision Pro (primary) + iPad/iPhone (validation) |
| **Challenge Statement** | Helping individuals achieve balance through authentic self-alignment |
| **App Statement** | An app that helps a person decide whether a future they're chasing is truly theirs — by letting them *walk through* an honest preview of that path's cost before they commit to it. |
| **Reframed core belief** | Balance is **not** a place you escape to. It is the steadiness of having seen the full cost of a path and still choosing it — or clearly choosing not to. Misalignment = chasing an unexamined fantasy, or fleeing a calling out of fear. |

**The reframe (vs PRD v0.1):** v0.1 said "self-alignment = balance; you can't align with a self
you don't know." We keep the AFP challenge but sharpen it: **you can't align with a *future*
you've never honestly looked at.** Most balance apps offer escape (an ethereal beach). Visual
Eyes does the opposite — it makes the cost of a chosen future *visible and walkable*, so the
choice is made with eyes open.

**Inspiration:** the *7 Up / Up* documentary series — plain, unsentimental, second-person.

**Scope (stated honestly):** v1 is about **honest preview → help you decide**. Daily
maintenance / "return to your space" is a later direction, out of scope here.

---

## 2. Target User

**Primary persona: Aisha Mensah — "I Am What I Produce"** (achievement-driven; AFP day-05 notes)

- 22, second-year IT student, UTS
- Equates productivity/achievement with wellbeing; doesn't know who she is beyond being a
  "high-achieving student"; skips anything that looks like a "self-reflection" tool
- **Hook (entry point):** not wellness, but "**see your future as a trailer**" — a 2-minute
  prompt generates a cinematic, walkable preview of the life she's chasing. Low-commitment,
  shareable. The honest *cost* of that future surfaces only once she's inside, walking it.

---

## 3. Core User Flow

```
Splash
    ↓
Questions  ("Who do you want to become?" + a few cost-point questions)
    ↓
"Building your museum…"  (Stage A writes the story → Stage B paints 5 images)
    ↓
Walk your 3D museum  (5 images on the walls; a documentary voice narrates each on approach)
    ↓
Talk with the Curator  (push-to-talk; it answers about THIS exhibition)
    ↓
The decision  (one closing question that calls back your own words; the choice is yours)
    ↓
Exit
```

User stories:
1. As a user, I want to name a future I'm chasing and get an honest preview of it, so I can feel its cost — not just imagine its glory.
2. As a user, I want to walk through that preview in 3D and hear it narrated, so it lands emotionally, not just intellectually.
3. As a user, I want to be asked one honest question at the end, so I leave with a clearer choice rather than a slogan.

---

## 4. Question Design

> The questions are the **inverse of the Hero's Journey**: we only ask for the personal beats
> the AI can't invent, and let the Curator invent the connective tissue (mentor, tests, scene
> detail). This preserves the "type one thing and watch it come alive" magic.

| Field | Question (UI copy) | Required | Feeds the beat |
|---|---|---|---|
| `role` | "Who do you want to become?" | ✅ Yes | The Call (beat 1) |
| `age` | "How old are you?" (stepper) | anchor | Ordinary World's starting age |
| `city` | "Where do you live?" | anchor | localizes the Elixir's landmark (beat 5) |
| `fear` | "What's been stopping you?" | optional | The Refusal (shadows beat 1) |
| `sacrifice` | "What are you least willing to give up for it?" | optional | The Sacrifice (beat 4) |
| `worthIt` | "What would make it worth it — even if you never make it?" | optional | The Elixir's meaning (beat 5) + the decision prompt |

- **Typed-first.** AI-voice-mentor input is a later upgrade — the input layer is decoupled from
  the story→image pipeline, so swapping typed → voice touches nothing downstream. (Meta-narratively,
  the voice mentor *is* the Mentor beat.)
- Blank optionals are **inferred by the Curator** from the archetype, so a one-field answer still
  produces a complete, non-generic story.
- UI copy is English (Sydney student persona).

---

## 5. Story Model — the five beats

The Curator writes a fixed **5-beat monomyth**. Four beats are the **cost** (cold-toned); one is
the **summit** (warm-toned). This 4:1 cost-to-glory ratio is the dividing line versus a vision
board.

| # | `stage` | What it shows | Tone |
|---|---|---|---|
| 1 | `ordinary_world_call` | Who they are now + the moment the dream calls (shadowed by their `fear`) | cold |
| 2 | `crossing_threshold` | They commit; the unglamorous grind begins | cold |
| 3 | `ordeal` | The lowest point — a kind of death (heaviest beat) | cold |
| 4 | `sacrifice` | What the path quietly cost them elsewhere (their `sacrifice`) | cold |
| 5 | `return_elixir` | The summit; the one triumphant image (their `worthIt`, localized to `city`) | warm |

**Honesty lives in the words and the choice — not in a grim image.** Beat 5's image stays
triumphant (also the safest to generate and pass moderation), but its *narration* states that
most who start never arrive, and the closing **`decision_prompt`** calls back the user's own
`fear` and `worthIt`, then ends on a question that hands the choice back — persuading neither way.

**Cost imagery is symbolic, never literal.** Cost is expressed through objects, spaces, and
light (an empty chair, frayed shoes, an unanswered phone, rain on a window) — never blood,
wounds, funerals, or faces in distress, and never readable text. This both dodges image-model
content moderation *and* is artistically stronger. Beats 1–4 share one locked "cold" style
string; beat 5 uses the "warm" style — keeping the five images visually consistent.

---

## 6. Technical Architecture

**Strategy:** one Xcode project, shared core logic, a display layer that differs only between
iPad (first-person) and visionOS (true immersion).

### 6.1 Generation pipeline (two stages, both OpenAI over `URLSession`)

```
MuseumAnswers
   │ Stage A — CuratorService
   │   OpenAI Responses API · model gpt-5.5 · strict text.format json_schema
   ▼
MuseumStory  { persona, cold_style, warm_style, decision_prompt, nodes:[5 × MuseumNode] }
   │ Stage B — ImageGenerationService
   │   OpenAI Images API · model gpt-image-2 · 5 prompts in parallel (TaskGroup)
   ▼
5 images (beat order)
```

- Stage A is constrained by a strict JSON schema, so the model's output decodes straight into
  `MuseumStory`. A few-shot dancer example teaches the tone, the cost ratio, and the symbolic,
  text-free imagery. Transient 5xx/Cloudflare errors self-heal via a shared retry helper.
- Stage B fires all five `image_prompt`s concurrently; each is self-contained (already begins
  with the locked style string), so there is no second LLM call to fail. A failed beat degrades
  to a placeholder image **without losing its slot**, so frame *i* always shows beat *i*.

### 6.2 Display — the pre-downloaded 3D museum

- **Asset:** the **Richards Art Gallery USDZ** (bundled / pre-downloaded), rendered with
  RealityKit. The 5 images are hung on the gallery's wall frames by
  `ParametricWorldBuilder.applyGalleryPhotos` (it textures every `bake`-named frame mesh, in beat
  order).
- **visionOS:** an `ImmersiveSpace` (`ImmersiveWorldView`); the head is the camera (head
  tracking) and a game controller / on-screen pad drives artificial locomotion
  (`ParametricLocomotor` + `SplatLocomotion`) so the user can walk a museum larger than the room.
- **iPad/iPhone:** the same USDZ in a first-person `ParametricWorldView` (camera rig + gestures),
  for validation without a headset.

### 6.3 Voice — narration + conversation (one voice authority)

- `ConversationService` orchestrates the loop: microphone → `SpeechRecognizer` (STT) → Claude
  Messages API (over `URLSession`) → TTS. TTS prefers a cloud voice (Azure, else ElevenLabs) and
  **falls back to on-device `AVSpeechSynthesizer`**, so the guide is never left silent.
- **Per-beat narration** (one-way): as the user walks within range of frame *i*, the Curator
  speaks `nodes[i].narration` once. Narration and conversation route through the **same**
  `ConversationService` instance so they share the audio session and never talk over each other.
- **Conversation** (push-to-talk): tapping the floating orb starts listening; the Curator answers
  about *this* exhibition, grounded in the story + the user's `fear`/`sacrifice`/`worthIt`, in
  2–3 spoken sentences, handing the choice back rather than persuading.

---

## 7. Data Model

```swift
// Sources/Museum/MuseumModels.swift
struct MuseumAnswers { var role, city, fear, sacrifice, worthIt: String; var age: Int }

struct MuseumNode: Codable, Identifiable {     // one of the five beats
    let stage: String        // ordinary_world_call | crossing_threshold | ordeal | sacrifice | return_elixir
    let age: Int
    let beat: String
    let narration: String
    let image_prompt: String // self-contained — already includes the style string
    let tone: String         // "cold" (beats 1–4) | "warm" (beat 5)
}

struct MuseumStory: Codable {
    let persona: String
    let cold_style, warm_style: String
    let decision_prompt: String
    let refusal: String?     // non-nil only if the Curator declined the goal
    let nodes: [MuseumNode]
}

@Observable final class GeneratedNode { let node: MuseumNode; var image: Data?; var failed: Bool }
```

The earlier `World` / `WorldParams` / `AxisScores` types still exist: `WorldParams` backs the
gallery archetype (light/locomotion) and the older parametric-world path (see §9).

---

## 8. Phasing

| Phase | Goal | External sign-up | Status |
|---|---|---|---|
| **1** | Generation pipeline: questions → Curator story → 5 images → flat gallery | OpenAI key | ✅ done (`feat/future-museum`) |
| **2** | **Bridge to the 3D walkable museum + Curator voice** (narration + push-to-talk) | OpenAI key (+ optional Anthropic) | 🔵 in progress |
| **3** | Voice input on the questions · streaming generation ("walk = loading bar") · cross-image style-lock | — | ⬜ next |
| **4** | Deploy on Apple Vision Pro hardware | Apple Developer (free tier) | ⬜ later |

> **"Walk = loading bar" (phase 3):** to hide live-generation latency, only beat 1 must be ready
> to enter; the rest stream onto the walls as the user walks (lobby narration covers the wait).
> A pre-cached fallback image set is swapped in if a live image fails/times out. Phase 2 keeps it
> simple: **generate all five first, then enter.**

---

## 9. Earlier explorations (kept, not the current spine)

These fed the current design and their code still lives in the repo — don't mistake them for dead:

- **Parametric world + quiz** (`Sources/Quiz`, `WorldMapper`, `AxisScores` → `WorldParams`): a
  4+1-axis personality quiz mapping to a continuously-tuned USDZ world. The gallery archetype
  reuses this builder.
- **Walkable Gaussian-splat spike** (`Sources/Spikes`, World Labs Marble `.spz`, 6DoF via
  CompositorServices / MetalSplatter): the "heavy" walkable-world path; the basis for live
  AI-generated worlds in a possible future phase.
- **Oops glass flow** (`Sources/Oops`): a dark-glass visionOS prototype (onboarding → quiz →
  gallery → reflection) and an earlier, *inspiring*-toned Hero's-Journey image gallery. The
  Museum is the *honest*-toned successor; the Oops flow is kept behind its own Dev Menu entry.

---

## 10. Research Still Needed (stated honestly)

1. **Question design** — does "Who do you want to become?" plus three cost-points truly elicit a
   real aspiration (vs a passing fancy)? Needs user testing.
2. **Visual consistency** — keeping the five generated images recognizably one series (style-lock;
   possibly a reference-image edit chain beat-1 → 2–5).
3. **Museum fps on device** — the Richards USDZ frame rate on actual Vision Pro hardware.
4. **Moderation robustness** — how reliably the symbolic cost imagery passes the image model.
5. **Voice latency & naturalness** — only judgeable in the headset; plus the on-device vs cloud
   TTS trade-off and voice-data privacy.
6. **Cost** — live GPT story + 5 images per visit; whether to cache / pre-generate for demos.

---

## 11. Tech Stack

| Item | Choice |
|---|---|
| Language / UI | Swift · SwiftUI |
| 3D | RealityKit; visionOS `ImmersiveSpace`; iPad `RealityView` + camera rig |
| Story generation | OpenAI **Responses API**, `gpt-5.5`, strict `json_schema` (`CuratorService`) |
| Image generation | OpenAI **Images API**, `gpt-image-2` (`ImageGenerationService`) |
| Conversation LLM | Anthropic Claude Messages API (`claude-haiku-4-5`) over `URLSession` |
| Speech input (STT) | Speech framework (`SFSpeechRecognizer`) |
| Speech output (TTS) | on-device `AVSpeechSynthesizer` (default, no key); **Azure** / **ElevenLabs** as cloud upgrades with automatic fallback |
| Networking | `URLSession` (no third-party packages) |
| IDE | Xcode 26.5 |

---

## 12. v1 (Phase 2) Definition of Done

- [ ] Splash → Questions (role required) → "Building your museum…"
- [ ] Stage A produces a valid 5-beat `MuseumStory`; Stage B paints 5 images (beat order, failures placeheld)
- [ ] visionOS: enter the Richards Gallery `ImmersiveSpace` with the 5 images on the walls
- [ ] Walk up to a frame → hear that beat's narration once (Curator voice)
- [ ] Tap the orb → speak → hear a grounded Curator reply (push-to-talk)
- [ ] Reach the Elixir → hear the closing `decision_prompt`; Leave returns cleanly
- [ ] Degrades gracefully: no Anthropic key → narration still speaks (AVSpeech), conversation shows an add-key notice, no crash

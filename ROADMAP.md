# Roadmap — Visiting Artisan

> Last aligned to code state: `dab3c9d` (feat/v2-foundation, 2026-05-28)

What's actually being built right now, what's on hold, and what the decision
gates are. For the product thesis see [PRD.md](PRD.md); for code structure see
[ARCHITECTURE.md](ARCHITECTURE.md); for asset coverage see [WORLDS.md](WORLDS.md).

This file is the **truth file for direction** — when a teammate asks "is the
spike still on?" or "did we choose Marble?", read here.

---

## Project context

- 3-person Apple Foundation Program group project + personal portfolio
- 3-week build window, Day 2 of 21 as of this update
- Vision Pro hardware arrives mid-Week 2
- Current focus per group: 3D world creation / walkability. Quiz design is
  parked as a research gap (see [PRD.md](PRD.md) §9).

---

## Three pipelines, side by side

| Pipeline | Status | Where to look | What blocks "ship it" |
|---|---|---|---|
| **3DoF equirectangular skybox** | 🟢 Primary, working | [`Immersive360View`](Sources/Immersive360View.swift) (iOS), [`ImmersiveWorldView`](Sources/ImmersiveWorldView.swift) (visionOS) | 2 of 4 worlds still need skybox assets (see [WORLDS.md](WORLDS.md)) |
| **6DoF USDZ walkable spike** | 🟡 In progress, Day 1 of 3 | [`Scene3DView`](Sources/Scene3DView.swift), [`SceneLoader`](Sources/SceneLoader.swift), [`Sources/Resources/Scenes/`](Sources/Resources/Scenes/) | Day 2 joystick + visionOS sibling; Day 3 hardware review; 2 of 4 USDZ assets missing |
| **WorldLabs API spike** | 🔴 Inert without key, not integrated | [`WorldLabsService`](Sources/WorldLabsService.swift), [`WorldLabsTestView`](Sources/WorldLabsTestView.swift), Splash → "Experimental: World Labs" | Not on critical path; kept visible for v2 evaluation |

---

## 6DoF spike — current focus

**Goal:** decide by end of Day 3 whether to commit to walkable USDZ worlds,
revert to 3DoF skybox, or take a third path. The spike preserves the existing
3DoF code 1:1 so it's fully revertable.

### Decision gate (at end of Day 3)

| Condition | Action |
|---|---|
| Vision Pro device sustains ≥60 fps in `warm_communal` AND walking feels natural to 2/2 testers AND USDZ scale only needs uniform fix AND we can source the remaining 2 USDZ assets within 1 week | **PROCEED** — write plan v3, full 6DoF pivot, archive 3DoF as fallback |
| <45 fps OR motion sickness OR scale needs significant rework OR remaining assets blocked | **RETREAT** — stop spike, return to 3DoF skybox + voice-over plan |
| 3DoF visuals feel limiting but 6DoF can't ship in 3 weeks | **DETOUR** — keep 3DoF architecture, upgrade visuals via Skybox AI Essential / Marble Pro |

### Day-by-day progress

| Day | Work | Status |
|---|---|---|
| **Day 1** | Source 3 USDZ candidates, copy into repo, add `World.sceneName`, write `SceneLoader` + `Scene3DView` (iOS, drag only), wire 6DoF entry button in iOS `WorldView`, build verification | ✅ Done (committed in `dab3c9d`) |
| **Day 2** | `VirtualJoystick.swift`, joystick → `Scene3DView` camera walk, `ImmersiveScene3DView.swift` + sibling `ImmersiveSpace(id: "world_3d")`, button in visionOS `WorldView` | ⏳ Pending |
| **Day 3** | Vision Pro device test, 2 teammate iPad playtests, capture fps + qualitative notes, hold decision gate meeting | ⏳ Pending |

---

## WorldLabs API spike — disposition

**Stays in the build target.** The team wants the spike visible while deciding
whether to integrate it as a future "live generation" path. It's reached only
via the Splash → "Experimental: World Labs" button — not from the main quiz
flow.

| Question | Current answer |
|---|---|
| Does it block clean-clone build? | ❌ No. `Secrets.swift` is committed with an empty key; the spike reports "Missing API key" and stays inert. |
| Is it on the 3-week roadmap? | ❌ No. It's a v2 candidate. |
| Should we remove it? | ❌ No (per group decision). Keep it as a visible reference implementation. |
| Should it be quarantined to `Sources/Experimental/`? | ❌ No (per group decision). It's a small build-target footprint. |
| What's the long-term plan? | Decide after 6DoF spike outcome. If RETREAT or DETOUR, World Labs Marble Pro $35/mo is one of the visual-upgrade paths. |

---

## What's NOT happening (and why)

| Path | Why not |
|---|---|
| World Labs Marble walkable (Gaussian splats, original PRD v4) | Splat rendering on visionOS needs MetalSplatter + custom shaders ≈ 3–6 weeks. Out of 3-week scope. The 6DoF USDZ spike is the lighter alternative. |
| Skybox AI live generation (original PRD v2) | API tier is Business $112/mo. Manual generation on free tier is OK but doesn't justify the architecture investment in 3 weeks. |
| Google Genie 3 | $250/mo, US-only, browser-only — no asset export possible. |
| Google SIMA 2 | Limited research preview, no public access, also an agent (not a world generator). |
| Bidirectional AI dialogue (SFSpeechRecognizer + LLM + TTS) | Phase 2 stretch after 3-week ship. |

---

## Research gaps (open questions)

These don't block the build but should be resolved before AFP submission.

1. **Quiz dimension design** — code carries five questions (`energy / need / help / week / minutes`); original PRD framed three dimensions (Emotional / Cultural / Physical). The group hasn't re-converged. **Target resolution: Week 1.5.**
2. **Cultural mapping** — the warm-communal vs quiet-solitary split was meant to encode collective vs individual cultural preference. Currently unverified that quiz answers actually distinguish that.
3. **6DoF outcome integration** — if the spike PROCEEDs, voice-over narration (currently planned as 3DoF feature) needs to be re-mapped onto the walkable experience.

---

## Next-up checklist (after this doc set lands)

1. Continue 6DoF spike Day 2 (joystick + visionOS sibling) — preferred, per group focus
2. OR rewrite [PRD.md](PRD.md) to align with this snapshot (separate planned batch)
3. OR investigate and fix the AppIcon error Codex flagged (on `main` branch) — verified absent in `feat/v2-foundation`

Default next step is (1); decide based on team availability.

# How the Museum makes & places its images

> Visual Eyes does **not** ship pre-baked 360° panoramas anymore. Each visit generates **five
> images** live from the user's answers, and hangs them on the walls of the pre-downloaded
> Richards Gallery USDZ. This doc explains how those images are authored and placed.
>
> *(Superseded: the old "generate 3 equirectangular `world_*` skybox images" method is gone.)*

---

## The five images

One image per Hero's-Journey beat (see [PRD.md](PRD.md) §5). Four are the **cost** (cold), one is
the **summit** (warm):

| # | Beat | Tone | Example symbolic image (dancer) |
|---|---|---|---|
| 1 | `ordinary_world_call` | cold | a single ballet flyer in a half-open desk drawer at dusk |
| 2 | `crossing_threshold` | cold | worn pointe shoes with frayed ribbons on a cold 5am studio floor |
| 3 | `ordeal` | cold | a long row of empty folding chairs, a single crutch at the end |
| 4 | `sacrifice` | cold | a phone face-up showing missed calls, a cold untouched cup of tea |
| 5 | `return_elixir` | warm | the Sydney Opera House stage from the wings during a curtain call |

The prompts are written by the **Curator** (Stage A), not by hand — each `MuseumNode.image_prompt`
is self-contained and already begins with the run's locked style string.

---

## Imagery rules (enforced by the Curator system prompt)

These rules live in `Sources/Museum/MuseumPrompt.swift` and keep the series consistent, artful,
and past content moderation:

1. **Symbolic only.** Express cost through **objects, spaces, and light** — never blood, wounds,
   illness, death, funerals, or faces in distress.
2. **No people as the subject, no recognizable faces.** Imply presence only through traces (a coat
   left behind, a shadow).
3. **No text, words, signage, or logos** in the image.
4. **One locked style per run.** Beats 1–4 share a single `cold_style` string (e.g. *"desaturated
   documentary photography, 35mm film grain, muted cold palette, soft natural window light,
   shallow depth of field, no people, no text"*); beat 5 uses the `warm_style` (e.g. *"warm
   cinematic photography, golden stage light, rich but restrained color"*). Locking the style is
   what keeps the five images recognizably one series.
5. **Personalized.** `role` drives the craft-specific imagery; `city` localizes beat 5's landmark;
   `fear` shadows beat 1; `sacrifice` drives beat 4.

---

## How an image reaches a wall

```
MuseumNode.image_prompt
   │ ImageGenerationService.image(forPrompt:)   (OpenAI Images, gpt-image-2, 1536×1024 PNG b64)
   ▼
image Data  →  UIImage
   │ MuseumGenerator.orderedGalleryImages()      (fixed 5-slot, beat order; placeholder if a beat failed)
   ▼
AppState.galleryImages: [UIImage]
   │ ParametricWorldBuilder.applyGalleryPhotos(model, textures:)
   ▼
each `bake`-named wall frame in the Richards Gallery USDZ shows image i  (beat i == frame i)
```

- **Beat order is the frame order.** `applyGalleryPhotos` collects the gallery's `bake`-named
  frame meshes in a stable order and assigns image *i* to frame *i*. The same ordered list drives
  the per-beat voice narration, so the image on a wall and the voice that describes it always match.
- **Failure degrades gracefully.** If a single beat's image fails to generate, its slot keeps a
  neutral placeholder texture (so the 5-slot mapping never shifts) and the visit still completes —
  the user is never trapped.

---

## Generating without live keys (for demos / offline)

- The on-device **narration voice needs no key** (`AVSpeechSynthesizer`), so you can walk the
  museum and hear the beats even with no network.
- The images themselves require a real `openAIAPIKey` (see [SETUP.md](SETUP.md)). With no key, the
  walls fall back to bundled placeholder textures so the 3D walkthrough still runs.
- To inspect a generated run outside the app, the series is also written to
  `Documents/GalleryJourney/scene_0X.png` (best-effort, reset each run).

---

## Swapping the museum asset

The 3D museum is the bundled **Richards Art Gallery USDZ** (`Sources/Spikes/SpikeAssets/`). To use
a different museum model, drop in a new USDZ whose picture-frame meshes contain `bake` in their
names (or update the selector in `ParametricWorldBuilder.applyGalleryPhotos`), keeping **at least
5** frames so all five beats land on distinct walls in walk order.

# Worlds — Asset Manual

> Last aligned to code state: `dab3c9d` (feat/v2-foundation, 2026-05-28)

What each of the four worlds is, which assets it currently has, and where to
find license-clean replacements. See [WorldCatalog.swift](Sources/WorldCatalog.swift)
for the runtime catalog and [ARCHITECTURE.md](ARCHITECTURE.md) §2 for how each
asset type is rendered.

---

## The four worlds

| ID | Title | 3DoF skybox asset | 6DoF USDZ asset | Quiz trigger (simplified) |
|---|---|---|---|---|
| `starry_night` | Under a Sky Made of Quiet | ❌ missing → gray sphere | ❌ missing → placeholder cube | Night context + solitary need |
| `open_nature` | A Horizon With Room to Move | ✅ `world_open_nature.imageset` | ✅ `world_open_nature.usdz` | High energy / nature need / active help |
| `warm_communal` | A Room That Lets You Exhale | ❌ missing → gray sphere | ✅ `world_warm_communal.usdz` | Communal cues / home / connection |
| `quiet_solitary` | A Quiet Worth Returning To | ✅ `world_quiet_solitary.imageset` | ❌ missing → placeholder cube | Quiet / alone / low energy / exam / focus |

> The mapping logic lives in `WorldCatalog.resolve()`; see
> [ARCHITECTURE.md](ARCHITECTURE.md) §6 for the full priority order.

**Coverage right now:** 2 of 4 worlds have a 3DoF skybox; 2 of 4 have a 6DoF
USDZ. The missing slots fall back gracefully (gray sphere or placeholder cube)
so the demo never crashes mid-quiz.

---

## Asset naming convention

| Where | Convention | Example |
|---|---|---|
| Skybox (equirectangular JPG) | `Assets.xcassets/world_<id>.imageset/` | `world_open_nature.imageset/` |
| USDZ scene | `Sources/Resources/Scenes/world_<id>.usdz` | `Sources/Resources/Scenes/world_warm_communal.usdz` |

The `<id>` must match `World.id` in `WorldCatalog.all` exactly. Lookup is by
name string; missing assets do not error — they go through the catalog's
graceful fallback path.

---

## 3DoF skybox assets (equirectangular)

**Format:** 2:1 aspect ratio (equirectangular projection). 4K (4096×2048) is
the recommended minimum; 8K is nicer but bundle size grows.

### Asset slots

| World ID | imageset present? | Source / next step |
|---|---|---|
| `starry_night` | ❌ | Suggested: [ESO — Milky Way at Chajnantor (UHD equirectangular)](https://www.eso.org/public/images/uhd_9428_panorama_eq/) (CC BY 4.0, attribution required) |
| `open_nature` | ✅ committed | Replace with [Poly Haven `lakeside`](https://polyhaven.com/a/lakeside) or `goegap` (CC0) for higher fidelity |
| `warm_communal` | ❌ | Suggested: filter [Poly Haven HDRIs](https://polyhaven.com/hdris) by `indoor` + `artificial light` + `low contrast`; e.g. [`resting_place`](https://polyhaven.com/a/resting_place) (CC0) |
| `quiet_solitary` | ✅ committed | Could swap for a minimal Poly Haven indoor + natural light HDRI |

### How to add a skybox

1. Save the panorama as a JPG (HDR works too, but JPG keeps the bundle small).
2. Drag it into Xcode under `Assets.xcassets/`. Use the asset name
   `world_<id>` (no extension, no spaces).
3. Build. The 3DoF pipeline will pick it up automatically — no code change
   needed.

---

## 6DoF USDZ assets (walkable scenes)

**Format:** Native `.usdz` (preferred — RealityKit loads it directly).
GLB can be converted to USDZ via Reality Composer Pro.

### Asset slots

| World ID | USDZ present? | Source |
|---|---|---|
| `starry_night` | ❌ | Hard to source — cosmic isn't a walkable place. Hybrid options: an observatory deck, a campsite under stars, a rooftop scene. Search Sketchfab for `observatory`, `campsite night`, `rooftop night`. |
| `open_nature` | ✅ committed | `world_open_nature.usdz` — sourced from [Sketchfab "FREE Dirt Road Through Forest"](https://sketchfab.com/3d-models/free-low-poly-forest-6dc8c85121234cb59dbd53a673fa2b8f) (downloadable) |
| `warm_communal` | ✅ committed | `world_warm_communal.usdz` — sourced from [Sketchfab "Cozy living room baked"](https://sketchfab.com/3d-models/cozy-living-room-baked-581238dc5fda4dc990571cdc02827783) (downloadable) |
| `quiet_solitary` | ❌ | Search keywords: `minimal room`, `zen room`, `empty studio`, `tatami`, `reading nook` on [Sketchfab Downloadable + CC0/CC BY](https://sketchfab.com/search?features=downloadable&licenses=322a749bcfa841b29dff1e8a1bb74b0b&q=minimal+room&type=models) |

### How to vet a candidate USDZ

Before committing, verify in this order:

1. **License** — must be CC0 or CC Attribution. Never NonCommercial.
2. **Format** — `.usdz` preferred; `.glb` is OK but convert via Reality Composer Pro.
3. **Scope** — must be a **scene** (a room or landscape) you can walk into, not
   a single prop.
4. **File size** — 50–300 MB. Smaller may be too sparse; larger will slow startup.
5. **Lighting baked** — open with macOS Quick Look. If the scene looks black or
   flat, it's relying on real-time lighting we don't have.
6. **Scale** — the model should be roughly human-sized. If you spawn inside a
   wall or float in space, the model is in wrong units.
7. **Polygons** — target under 500K triangles for Vision Pro at 90 fps.

### How to add a USDZ

1. Drop the `.usdz` into `Sources/Resources/Scenes/` with the name
   `world_<id>.usdz`.
2. Register it in `VisitingArtisan.xcodeproj/project.pbxproj` as a Resources
   build phase entry (Xcode's "Add Files…" dialog with target membership
   checked does this for you).
3. Set the matching `sceneName: "world_<id>"` on the world entry in
   [`WorldCatalog.swift`](Sources/WorldCatalog.swift).
4. Build. `SceneLoader` will pick it up; the fallback cube disappears for that
   world.

---

## License-clean asset sources

### Photo-based panoramas (3DoF)

- [Poly Haven](https://polyhaven.com/hdris) — CC0, 4K–16K, no login. **First stop.**
- [ESO](https://www.eso.org/public/images/) — CC BY 4.0 (attribution required), best for astronomy / cosmic content.
- [HDRI Hub free samples](https://www.hdri-hub.com/hdrishop/freesamples/freehdri) — interior coverage is decent here.
- [HDRMAPS freebies](https://hdrmaps.com/freebies/) — variety, commercial OK.

### 3D scenes (6DoF)

- [Sketchfab](https://sketchfab.com/search?features=downloadable) — filter
  Downloadable + CC0 or CC Attribution. Biggest catalog.
- [Poly Pizza](https://poly.pizza/) — Google's CC0 successor library; mostly
  objects, some scenes.
- [Meshy](https://www.meshy.ai/tags/environment) — CC0, USDZ export available.
- [Quixel Megascans](https://quixel.com/megascans) — AAA scans, free with an
  Epic account, commercial OK.

### AI generators (note licensing carefully)

- [Skybox AI (Blockade Labs)](https://www.blockadelabs.com/) — Essential plan
  $20/mo gets 8K equirectangular + commercial license. Free tier **cannot
  export**.
- [World Labs Marble](https://marble.worldlabs.ai/) — Standard tier $20/mo is
  **non-commercial only**; Pro $35/mo includes commercial. The 360° panorama
  export option works for our skybox pipeline if you do go paid.

> Be careful with World Labs: free / Standard outputs are personal,
> non-commercial use only — that's a problem for a public portfolio. See
> [ROADMAP.md](ROADMAP.md) for the project's stance on each generator.

---

## What "missing asset" looks like in the app

- **3DoF / skybox path:** the inward-facing sphere gets a flat gray material
  (`tint: white 0.25`) instead of the panorama texture. You can still drag /
  gyro / head-turn; the world is just unstyled.
- **6DoF / USDZ path:** [`SceneLoader.swift`](Sources/SceneLoader.swift)
  returns a gray cube (`MeshResource.generateBox(size: 0.5)`) positioned
  2 m in front of the camera. Future versions may attach a text label
  ("USDZ not available") via a RealityKit attachment.

Both fallbacks are explicit, never crash, and are friendly to demo recordings.

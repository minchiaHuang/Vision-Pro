# v1 — Producing the 3 pre-baked 360° world images

> v1 does not call any API; it bundles manually generated 360° images into the app.
> Key constraint: each image must be **equirectangular format with a 2:1 aspect ratio**,
> so it maps correctly onto the sphere.

---

## The 3 images to produce (matching WorldCatalog.swift)

| Asset name | World | Quiz trigger (cultural + physical) |
|---|---|---|
| `world_calm_communal` | Warm communal space (not empty, a sense of connection) | communal / home |
| `world_open_nature` | Open nature (mountains, sea, breathing room) | nature / explore / active |
| `world_quiet_solitary` | Quiet solitary space (negative space, stillness) | still / rest |

---

## Method A — Skybox AI (recommended; free tier, natively equirectangular)

1. Open https://skybox.blockadelabs.com/
2. Sign up for a free account
3. Generate each image with the matching prompt:

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

4. Download each one (Skybox output is already 2:1 equirectangular) and rename it to the
   asset name in the table above.

---

## Method B — Other tools (fallback)

| Tool | Notes |
|---|---|
| https://www.blockadelabs.com (same as above) | Most direct; natively 360° |
| Midjourney `--ar 2:1` + adding "equirectangular 360 panorama" | Correct ratio, but seams may not be perfect |
| Poly / existing HDRI asset libraries | Truly 360°, but not personalised |

⚠️ Images produced directly by typical Midjourney/DALL-E **are not true equirectangular**;
they distort at the seam and poles when mapped onto a sphere. Prefer Skybox AI.

---

## Adding them to Xcode

1. Open `Assets.xcassets`
2. Drag the 3 images in
3. The asset names must **exactly equal**: `world_calm_communal`, `world_open_nature`,
   `world_quiet_solitary`
4. Press ⌘R to run and test

---

## You can run before generating the images

When `Immersive360View` / `ImmersiveWorldView` can't find an image, it falls back to a dark
grey sphere, so you can **get the whole flow working first** (splash → quiz → loading →
looking around the world) and add the images later.

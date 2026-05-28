# Visiting Artisan — Build & Run

> Last aligned to code state: `dab3c9d` (feat/v2-foundation, 2026-05-28)

Reproducibility-focused setup for the SwiftUI iPad + Apple Vision Pro prototype.
For the product story see [PRD.md](PRD.md); for the code map see
[ARCHITECTURE.md](ARCHITECTURE.md).

---

## Requirements

- macOS with Xcode 26.5 or newer
- iOS 26 simulator runtime (default `iPad Pro 13-inch (M5)`)
- visionOS 26 simulator runtime (`Apple Vision Pro`)
- No external API keys required for the main demo flow

---

## Project

Single Xcode project, single target, multi-platform:

| Setting | Value |
|---|---|
| Project file | `VisitingArtisan.xcodeproj` |
| Scheme / target | `VisitingArtisan` |
| Bundle ID | `com.tommy.VisitingArtisan` |
| Supported platforms | `iphoneos iphonesimulator xros xrsimulator` |
| iOS deployment target | 26.0 |
| visionOS deployment target | 26.0 |
| Targeted device family | `1,2,7` (iPhone, iPad, Apple Vision) |

> The old docs described "two targets" — that's stale. The current project is a
> single target whose `SUPPORTED_PLATFORMS` covers iOS and visionOS.

---

## Run in Xcode

1. Open `VisitingArtisan.xcodeproj`.
2. Select the `VisitingArtisan` scheme.
3. Pick a destination:
   - `iPad Pro 13-inch (M5)` simulator — primary demo target
   - `Apple Vision Pro` simulator — immersive demo target
4. ⌘R.

Expected flow:

```
Splash  →  five-question quiz  →  Weaving (~2 s)  →  immersive world
```

From the World screen you can also tap **"View in 6DoF (spike)"** to enter the
walkable USDZ experiment (iOS path only at the moment).

---

## Clean-build verification

A scripted clean build for both simulators lives at [`bin/verify.sh`](bin/verify.sh):

```bash
bash bin/verify.sh
```

Expected output:

```
Visiting Artisan — clean-build verification
===========================================
→ Building iPad Pro 13-inch (M5) sim ... ✅ PASS
→ Building Apple Vision Pro sim ... ✅ PASS

Summary: 2 passed, 0 failed.
All builds succeeded.
```

Failure logs are preserved in a `/tmp/tmp.XXXXX` directory printed to stdout so
you can inspect them.

Each build takes 30–90 s. The script disables code signing
(`CODE_SIGNING_ALLOWED=NO`) so it runs without a developer account.

---

## Secrets and the WorldLabs spike

[`Sources/Secrets.swift`](Sources/Secrets.swift) is **committed** as an empty stub
so every clean clone builds out of the box:

```swift
enum Secrets {
    static let worldLabsAPIKey: String = ""
}
```

The Splash screen exposes an **"Experimental: World Labs"** button that opens
[`Sources/WorldLabsTestView.swift`](Sources/WorldLabsTestView.swift). With the
empty key this entry simply reports `"Missing World Labs API key (Secrets.swift)."`
and stays inert — this is the **expected** clean-clone behavior, not a bug.

If you need to test the WorldLabs spike locally:

1. Edit `Sources/Secrets.swift` with your own key.
2. Optionally protect against accidental commits:
   ```bash
   git update-index --skip-worktree Sources/Secrets.swift
   ```
3. Build and use the Splash button as before.

> ⚠️ Never commit a real key. The repo only carries the empty stub. See
> [ROADMAP.md](ROADMAP.md) for the WorldLabs pipeline status.

---

## Replacing world assets

The four catalog worlds reference asset names that may or may not exist in
`Assets.xcassets/` (skybox) or `Sources/Resources/Scenes/` (USDZ). Missing
assets fall back gracefully:

- 3DoF skybox: missing image → gray sphere (`Immersive360View`)
- 6DoF scene: missing USDZ → labelled placeholder cube (`SceneLoader`)

See [WORLDS.md](WORLDS.md) for required asset names, current status, and
license-clean download sources (Poly Haven CC0, ESO CC BY, Sketchfab).

---

## Known caveats

- **Old "Cmd-R"-style hard-coded simulator names** in archived docs may no longer
  exist on your machine. Use whatever is in `xcrun simctl list devices` or run
  `bin/verify.sh` which targets the canonical iPad Pro 13" (M5) and Apple Vision
  Pro names.
- **Two of the four catalog worlds (`warm_communal`, `starry_night`) currently
  have no skybox image.** They render as a gray sphere in the 3DoF path. The
  6DoF spike provides a USDZ for `warm_communal` but not yet `starry_night`.
- **The 6DoF spike entry point** is iOS-only right now (Day 1 of a 3-day spike).
  The visionOS sibling `ImmersiveSpace(id: "world_3d")` is on the Day 2 list.

---

## Command-line build (manual)

If you want to drive a single platform directly:

```bash
# iPad
xcodebuild -project VisitingArtisan.xcodeproj \
  -scheme VisitingArtisan \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  clean build

# Apple Vision Pro
xcodebuild -project VisitingArtisan.xcodeproj \
  -scheme VisitingArtisan \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Use a different `-derivedDataPath` per build if you want them to run in parallel.

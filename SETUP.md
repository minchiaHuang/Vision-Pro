# Visual Eyes — Build & Run

> The repo includes `VisitingArtisan.xcodeproj` (the Xcode project/target is still named
> `VisitingArtisan`; the product is **Visual Eyes**). You don't need to create a project or copy
> `Sources/` into a target.

---

## Project

Open:

```text
/Users/tommyhuang/Desktop/Vision-Pro/VisitingArtisan.xcodeproj
```

The `VisitingArtisan` target uses:

- Product name: `VisitingArtisan` (display name "Visual Eyes")
- Bundle ID: `com.tommy.VisitingArtisan`
- Shared SwiftUI source from `Sources/`
- Supported destinations: iPhone, iPad, Apple Vision
- Deployment targets: iOS 26.0 and visionOS 26.0

The core 3D walkthrough runs with no key (the museum USDZ is bundled and narration uses on-device
TTS). **Live image generation needs an `openAIAPIKey`** — without it, the walls fall back to
bundled placeholder textures so the flow still runs.

---

## Secrets / API keys

`Sources/Core/Secrets.swift` **is committed with empty placeholder keys** so a fresh clone builds
out of the box. There are no real keys in this repo, and you must never commit one.

The keys gate optional, layered features:

- `openAIAPIKey` — the **Future Museum** pipeline: Stage A `CuratorService` (story) + Stage B
  `ImageGenerationService` (images). Empty → the walls use bundled placeholders. Your account must
  expose `gpt-5.5` (Curator) and `gpt-image-2` (images); otherwise swap the model constants in
  those services.
- `anthropicAPIKey` — the push-to-talk **conversation** (Claude Messages API). Empty →
  `ConversationService` shows an add-key notice and conversation stays inert. **Per-beat narration
  still works**, since it uses only on-device TTS.
- `azureSpeechKey` / `elevenLabsAPIKey` — optional cloud **TTS** upgrades (Azure preferred). Empty
  → on-device `AVSpeechSynthesizer` is used automatically.
- `worldLabsAPIKey` — the experimental walkable-splat spike. Empty → `WorldLabsService` reports
  "Missing API key" and stays inert.

For local experiments, edit `Sources/Core/Secrets.swift` and keep the change unstaged. For extra
safety against accidental commits:

```bash
git update-index --skip-worktree Sources/Core/Secrets.swift
```

For any additional out-of-band secrets, use a `*.env` file or `APIKeys.plist` — both are gitignored.

---

## Run in Xcode

1. Open `VisitingArtisan.xcodeproj`.
2. Select the `VisitingArtisan` scheme.
3. Choose one of:
   - `iPad Pro 13-inch (M5)` simulator
   - `Apple Vision Pro` simulator
4. Press `Cmd-R`. From the Dev Menu, pick **Future Museum**.

Expected flow:

```text
Questions -> "Building your museum…" -> walk the 3D museum (5 images + narration) -> the decision
```

---

## Command-line Verification

List the project:

```bash
xcodebuild -list -project VisitingArtisan.xcodeproj
```

Build for iPad simulator:

```bash
xcodebuild -project VisitingArtisan.xcodeproj \
  -scheme VisitingArtisan \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Build for visionOS simulator:

```bash
xcodebuild -project VisitingArtisan.xcodeproj \
  -scheme VisitingArtisan \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

If running both builds at the same time, use separate `-derivedDataPath` values to avoid Xcode's build database lock.

---

## The museum's images

The museum's wall images are generated live per visit (see [WORLDS.md](WORLDS.md)). The 3D museum
asset itself is the bundled Richards Art Gallery USDZ in `Sources/Spikes/SpikeAssets/`. No image
assets need to be pre-baked or renamed.

# Visual Eyes — Build & Run

> v1 now includes `VisualEyes.xcodeproj` in this repo.
> You no longer need to create an Xcode project manually or copy `Sources/` into a target.

---

## Project

Open:

```text
/Users/tommyhuang/Desktop/Vision-Pro/VisualEyes.xcodeproj
```

The `VisualEyes` target uses:

- Product name: `VisualEyes`
- Bundle ID: `com.tommy.VisitingArtisan`
- Shared SwiftUI source from `Sources/`
- Supported destinations: iPhone, iPad, Apple Vision
- Deployment targets: iOS 26.0 and visionOS 26.0

No external API key is required for v1. The repo includes sample 360° images from the Skybox AI asset pack. If any image is missing later, the app falls back to a grey sphere so the full flow can still run.

---

## Secrets / API keys

`Sources/Secrets.swift` **is committed to the repo with empty placeholder keys** so that a
fresh clone builds out of the box. There are no real keys in this repo, and you must never
commit one.

The core flow needs no key. The two stub keys gate optional, experimental features only:

- `worldLabsAPIKey` — the experimental "World Labs" walkable-splat entry point. Empty →
  `WorldLabsService` reports "Missing API key" and stays inert.
- `anthropicAPIKey` — the Phase 6b two-way voice conversation (Claude Messages API). Empty →
  `ConversationService` reports "Missing API key" and the conversation stays inert. The 6a
  entry narration still works, since it uses only on-device TTS and needs no key.

For local experiments with a real key, edit `Sources/Secrets.swift` locally and keep the
change unstaged. For extra safety against accidental commits:

```bash
git update-index --skip-worktree Sources/Secrets.swift
```

For any additional out-of-band secrets, use a `*.env` file or `APIKeys.plist` — both are
gitignored.

---

## Run in Xcode

1. Open `VisualEyes.xcodeproj`.
2. Select the `VisualEyes` scheme.
3. Choose one of:
   - `iPad Pro 13-inch (M5)` simulator
   - `Apple Vision Pro` simulator
4. Press `Cmd-R`.

Expected v1 flow:

```text
Splash -> Quiz -> Building your world... -> sample 360 world
```

---

## Command-line Verification

List the project:

```bash
xcodebuild -list -project VisualEyes.xcodeproj
```

Build for iPad simulator:

```bash
xcodebuild -project VisualEyes.xcodeproj \
  -scheme VisualEyes \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Build for visionOS simulator:

```bash
xcodebuild -project VisualEyes.xcodeproj \
  -scheme VisualEyes \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

If running both builds at the same time, use separate `-derivedDataPath` values to avoid Xcode's build database lock.

---

## Replace 360° Images Later

The current images are sample assets. When final v1 world images are ready, replace the files in `Assets.xcassets` while keeping these exact asset names:

- `world_calm_communal`
- `world_open_nature`
- `world_quiet_solitary`

See [WORLDS.md](WORLDS.md) for generation guidance.

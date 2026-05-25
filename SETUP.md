# Visiting Artisan — Build & Run

> v1 now includes `VisitingArtisan.xcodeproj` in this repo.
> You no longer need to create an Xcode project manually or copy `Sources/` into a target.

---

## Project

Open:

```text
/Users/tommyhuang/Desktop/Vision-Pro/VisitingArtisan.xcodeproj
```

The `VisitingArtisan` target uses:

- Product name: `VisitingArtisan`
- Bundle ID: `com.tommy.VisitingArtisan`
- Shared SwiftUI source from `Sources/`
- Supported destinations: iPhone, iPad, Apple Vision
- Deployment targets: iOS 26.0 and visionOS 26.0

No external API key is required for v1. The repo includes sample 360° images from the Skybox AI asset pack. If any image is missing later, the app falls back to a grey sphere so the full flow can still run.

---

## Run in Xcode

1. Open `VisitingArtisan.xcodeproj`.
2. Select the `VisitingArtisan` scheme.
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

## Replace 360° Images Later

The current images are sample assets. When final v1 world images are ready, replace the files in `Assets.xcassets` while keeping these exact asset names:

- `world_calm_communal`
- `world_open_nature`
- `world_quiet_solitary`

See [WORLDS.md](WORLDS.md) for generation guidance.
